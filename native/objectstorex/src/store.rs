use object_store::list::{PaginatedListOptions, PaginatedListStore};
use object_store::path::{DELIMITER, Path};
use object_store::{DynObjectStore, ListResult, ObjectMeta, ObjectStore};
use std::borrow::Cow;
use std::cmp::Ordering;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::panic::RefUnwindSafe;
use std::sync::Arc;
use uuid::Uuid;

const FALLBACK_TOKEN_VERSION: &str = "obx1";

/// Result of listing one bounded delimiter-aware page.
pub struct ListPageResult {
    pub objects: Vec<ObjectMeta>,
    pub common_prefixes: Vec<Path>,
    pub next_page_token: Option<String>,
}

/// Errors specific to bounded delimiter-aware listing.
#[derive(Debug)]
pub enum ListPageError {
    InvalidPageToken,
    Store(object_store::Error),
}

impl From<object_store::Error> for ListPageError {
    fn from(error: object_store::Error) -> Self {
        Self::Store(error)
    }
}

enum PaginationCapability {
    Native(Arc<dyn PaginatedListStore>),
    Compatibility,
}

/// Wrapper around the object_store trait objects.
///
/// The ordinary object store is retained for all existing operations. Cloud
/// providers additionally retain their low-level paginated listing capability;
/// memory and local stores use the compatibility pager.
pub struct StoreWrapper {
    pub inner: Arc<DynObjectStore>,
    pagination: PaginationCapability,
    fallback_token_salt: u128,
}

impl StoreWrapper {
    pub fn new_native<T>(store: T) -> Self
    where
        T: ObjectStore + PaginatedListStore,
    {
        let store = Arc::new(store);
        let inner: Arc<DynObjectStore> = store.clone();
        let paginated: Arc<dyn PaginatedListStore> = store;

        Self {
            inner,
            pagination: PaginationCapability::Native(paginated),
            fallback_token_salt: Uuid::new_v4().as_u128(),
        }
    }

    pub fn new_compatibility<T>(store: T) -> Self
    where
        T: ObjectStore,
    {
        Self {
            inner: Arc::new(store),
            pagination: PaginationCapability::Compatibility,
            fallback_token_salt: Uuid::new_v4().as_u128(),
        }
    }

    pub async fn list_with_delimiter_page(
        &self,
        prefix: Option<String>,
        max_keys: usize,
        page_token: Option<String>,
    ) -> Result<ListPageResult, ListPageError> {
        let prefix_path = prefix.map(Path::from);

        match &self.pagination {
            PaginationCapability::Native(store) => {
                let normalized_prefix = normalize_native_prefix(prefix_path.as_ref());
                let result = store
                    .list_paginated(
                        normalized_prefix.as_deref(),
                        native_list_options(max_keys, page_token),
                    )
                    .await?;

                Ok(ListPageResult {
                    objects: result.result.objects,
                    common_prefixes: result.result.common_prefixes,
                    next_page_token: result.page_token,
                })
            }
            PaginationCapability::Compatibility => {
                let start = match page_token {
                    Some(token) => {
                        self.decode_fallback_token(&token, prefix_path.as_ref(), max_keys)?
                    }
                    None => 0,
                };

                let result = self.inner.list_with_delimiter(prefix_path.as_ref()).await?;

                Ok(self.compatibility_page(result, prefix_path.as_ref(), max_keys, start))
            }
        }
    }

    fn compatibility_page(
        &self,
        result: ListResult,
        prefix: Option<&Path>,
        max_keys: usize,
        start: usize,
    ) -> ListPageResult {
        let mut entries = Vec::with_capacity(result.objects.len() + result.common_prefixes.len());
        entries.extend(result.objects.into_iter().map(CompatibilityEntry::Object));
        entries.extend(
            result
                .common_prefixes
                .into_iter()
                .map(CompatibilityEntry::Prefix),
        );
        entries.sort_by(compare_compatibility_entries);

        let entry_count = entries.len();
        let page_start = start.min(entry_count);
        let page_end = page_start.saturating_add(max_keys).min(entry_count);
        let mut objects = Vec::new();
        let mut common_prefixes = Vec::new();

        for entry in entries.into_iter().skip(page_start).take(max_keys) {
            match entry {
                CompatibilityEntry::Object(meta) => objects.push(meta),
                CompatibilityEntry::Prefix(path) => common_prefixes.push(path),
            }
        }

        let next_page_token = (page_end < entry_count)
            .then(|| self.encode_fallback_token(prefix, max_keys, page_end));

        ListPageResult {
            objects,
            common_prefixes,
            next_page_token,
        }
    }

    fn encode_fallback_token(
        &self,
        prefix: Option<&Path>,
        max_keys: usize,
        offset: usize,
    ) -> String {
        let signature = self.fallback_token_signature(prefix, max_keys, offset);
        format!("{FALLBACK_TOKEN_VERSION}.{offset:x}.{max_keys:x}.{signature:016x}")
    }

    fn decode_fallback_token(
        &self,
        token: &str,
        prefix: Option<&Path>,
        max_keys: usize,
    ) -> Result<usize, ListPageError> {
        let mut parts = token.split('.');
        let version = parts.next();
        let offset = parts
            .next()
            .and_then(|value| usize::from_str_radix(value, 16).ok());
        let token_max_keys = parts
            .next()
            .and_then(|value| usize::from_str_radix(value, 16).ok());
        let signature = parts
            .next()
            .and_then(|value| u64::from_str_radix(value, 16).ok());

        if version != Some(FALLBACK_TOKEN_VERSION) || parts.next().is_some() {
            return Err(ListPageError::InvalidPageToken);
        }

        let (Some(offset), Some(token_max_keys), Some(signature)) =
            (offset, token_max_keys, signature)
        else {
            return Err(ListPageError::InvalidPageToken);
        };

        if offset == 0
            || token_max_keys != max_keys
            || signature != self.fallback_token_signature(prefix, max_keys, offset)
        {
            return Err(ListPageError::InvalidPageToken);
        }

        Ok(offset)
    }

    fn fallback_token_signature(
        &self,
        prefix: Option<&Path>,
        max_keys: usize,
        offset: usize,
    ) -> u64 {
        let mut hasher = DefaultHasher::new();
        FALLBACK_TOKEN_VERSION.hash(&mut hasher);
        self.fallback_token_salt.hash(&mut hasher);
        prefix.map(Path::as_ref).hash(&mut hasher);
        max_keys.hash(&mut hasher);
        offset.hash(&mut hasher);
        hasher.finish()
    }

    #[cfg(test)]
    fn uses_native_pagination(&self) -> bool {
        matches!(self.pagination, PaginationCapability::Native(_))
    }
}

fn native_list_options(max_keys: usize, page_token: Option<String>) -> PaginatedListOptions {
    PaginatedListOptions {
        delimiter: Some(Cow::Borrowed(DELIMITER)),
        max_keys: Some(max_keys),
        page_token,
        ..Default::default()
    }
}

fn normalize_native_prefix(prefix: Option<&Path>) -> Option<String> {
    prefix
        .filter(|path| !path.as_ref().is_empty())
        .map(|path| format!("{}{DELIMITER}", path.as_ref()))
}

enum CompatibilityEntry {
    Object(ObjectMeta),
    Prefix(Path),
}

impl CompatibilityEntry {
    fn path(&self) -> &Path {
        match self {
            Self::Object(meta) => &meta.location,
            Self::Prefix(path) => path,
        }
    }

    fn tie_breaker(&self) -> u8 {
        match self {
            Self::Object(_) => 0,
            Self::Prefix(_) => 1,
        }
    }
}

fn compare_compatibility_entries(
    left: &CompatibilityEntry,
    right: &CompatibilityEntry,
) -> Ordering {
    left.path()
        .cmp(right.path())
        .then_with(|| left.tie_breaker().cmp(&right.tie_breaker()))
}

// Implement RefUnwindSafe to satisfy Rustler's requirements
impl RefUnwindSafe for StoreWrapper {}

#[cfg(test)]
mod tests {
    use super::*;
    use object_store::aws::AmazonS3;
    use object_store::azure::MicrosoftAzure;
    use object_store::gcp::GoogleCloudStorage;
    use object_store::memory::InMemory;
    use object_store::{ObjectStoreExt, PutPayload};

    fn assert_native_provider<T: ObjectStore + PaginatedListStore>() {}

    #[test]
    fn cloud_provider_types_support_native_pagination() {
        assert_native_provider::<AmazonS3>();
        assert_native_provider::<MicrosoftAzure>();
        assert_native_provider::<GoogleCloudStorage>();
    }

    #[test]
    fn memory_store_selects_compatibility_pagination() {
        let store = StoreWrapper::new_compatibility(InMemory::new());
        assert!(!store.uses_native_pagination());
    }

    #[test]
    fn compatibility_order_uses_object_before_prefix_as_tie_breaker() {
        let object = CompatibilityEntry::Object(ObjectMeta {
            location: Path::from("same"),
            last_modified: chrono::Utc::now(),
            size: 0,
            e_tag: None,
            version: None,
        });
        let prefix = CompatibilityEntry::Prefix(Path::from("same"));

        assert_eq!(
            compare_compatibility_entries(&object, &prefix),
            Ordering::Less
        );
    }

    #[test]
    fn native_options_include_delimiter_limit_and_token() {
        let options = native_list_options(25, Some("provider-token".to_string()));
        assert_eq!(options.delimiter.as_deref(), Some(DELIMITER));
        assert_eq!(options.max_keys, Some(25));
        assert_eq!(options.page_token.as_deref(), Some("provider-token"));
        assert!(options.offset.is_none());
    }

    #[test]
    fn native_prefix_matches_object_store_path_segment_semantics() {
        assert_eq!(normalize_native_prefix(None), None);
        assert_eq!(normalize_native_prefix(Some(&Path::from("/"))), None);
        assert_eq!(
            normalize_native_prefix(Some(&Path::from("audio/"))),
            Some("audio/".to_string())
        );
    }

    #[tokio::test]
    async fn compatibility_pages_apply_one_combined_limit() {
        let memory = InMemory::new();
        memory
            .put(&Path::from("a.txt"), PutPayload::from_static(b"a"))
            .await
            .unwrap();
        memory
            .put(&Path::from("b/nested.txt"), PutPayload::from_static(b"b"))
            .await
            .unwrap();
        memory
            .put(&Path::from("c.txt"), PutPayload::from_static(b"c"))
            .await
            .unwrap();

        let store = StoreWrapper::new_compatibility(memory);
        let first = store.list_with_delimiter_page(None, 2, None).await.unwrap();
        assert_eq!(first.objects.len() + first.common_prefixes.len(), 2);
        assert_eq!(first.objects[0].location.as_ref(), "a.txt");
        assert_eq!(first.common_prefixes[0].as_ref(), "b");

        let second = store
            .list_with_delimiter_page(None, 2, first.next_page_token)
            .await
            .unwrap();
        assert_eq!(second.objects.len(), 1);
        assert!(second.common_prefixes.is_empty());
        assert_eq!(second.objects[0].location.as_ref(), "c.txt");
        assert!(second.next_page_token.is_none());
    }

    #[tokio::test]
    async fn compatibility_tokens_are_versioned_and_request_bound() {
        let memory = InMemory::new();
        for path in ["a", "b"] {
            memory
                .put(&Path::from(path), PutPayload::from_static(b"value"))
                .await
                .unwrap();
        }

        let store = StoreWrapper::new_compatibility(memory);
        let first = store.list_with_delimiter_page(None, 1, None).await.unwrap();
        let token = first.next_page_token.unwrap();
        assert!(token.starts_with("obx1."));

        assert!(matches!(
            store
                .list_with_delimiter_page(None, 2, Some(token.clone()))
                .await,
            Err(ListPageError::InvalidPageToken)
        ));
        assert!(matches!(
            store
                .list_with_delimiter_page(Some("other/".to_string()), 1, Some(token.clone()))
                .await,
            Err(ListPageError::InvalidPageToken)
        ));

        let other_store = StoreWrapper::new_compatibility(InMemory::new());
        assert!(matches!(
            other_store
                .list_with_delimiter_page(None, 1, Some(token))
                .await,
            Err(ListPageError::InvalidPageToken)
        ));
        assert!(matches!(
            store
                .list_with_delimiter_page(None, 1, Some("obx0.1.1.0".to_string()))
                .await,
            Err(ListPageError::InvalidPageToken)
        ));
    }
}
