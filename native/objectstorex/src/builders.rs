use crate::store::StoreWrapper;
use object_store::{
    aws::AmazonS3Builder, azure::MicrosoftAzureBuilder, gcp::GoogleCloudStorageBuilder,
    local::LocalFileSystem, memory::InMemory,
};
use rustler::{NifResult, ResourceArc};
use std::sync::Arc;

/// Create a new S3 object store
#[rustler::nif]
pub fn new_s3(
    bucket: String,
    region: Option<String>,
    access_key_id: Option<String>,
    secret_access_key: Option<String>,
    endpoint: Option<String>,
) -> NifResult<ResourceArc<StoreWrapper>> {
    let mut builder = AmazonS3Builder::new().with_bucket_name(bucket);

    if let Some(region) = region {
        builder = builder.with_region(region);
    }

    if let Some(key) = access_key_id {
        builder = builder.with_access_key_id(key);
    }

    if let Some(secret) = secret_access_key {
        builder = builder.with_secret_access_key(secret);
    }

    if let Some(ep) = endpoint {
        builder = builder.with_endpoint(ep);
    }

    let store = builder
        .build()
        .map_err(|e| rustler::Error::Term(Box::new(format!("S3 build error: {}", e))))?;

    Ok(ResourceArc::new(StoreWrapper::new(Arc::new(store))))
}

/// Create a new Azure Blob Storage object store
#[rustler::nif]
pub fn new_azure(
    account: String,
    container: String,
    access_key: Option<String>,
) -> NifResult<ResourceArc<StoreWrapper>> {
    let mut builder = MicrosoftAzureBuilder::new()
        .with_account(account)
        .with_container_name(container);

    if let Some(key) = access_key {
        builder = builder.with_access_key(key);
    }

    let store = builder
        .build()
        .map_err(|e| rustler::Error::Term(Box::new(format!("Azure build error: {}", e))))?;

    Ok(ResourceArc::new(StoreWrapper::new(Arc::new(store))))
}

/// Create a new Google Cloud Storage object store
#[rustler::nif]
pub fn new_gcs(
    bucket: String,
    service_account_key: Option<String>,
) -> NifResult<ResourceArc<StoreWrapper>> {
    let mut builder = GoogleCloudStorageBuilder::new().with_bucket_name(bucket);

    if let Some(key) = service_account_key {
        builder = builder.with_service_account_key(key);
    }

    let store = builder
        .build()
        .map_err(|e| rustler::Error::Term(Box::new(format!("GCS build error: {}", e))))?;

    Ok(ResourceArc::new(StoreWrapper::new(Arc::new(store))))
}

/// Create a new local filesystem object store
#[rustler::nif]
pub fn new_local(path: String) -> NifResult<ResourceArc<StoreWrapper>> {
    let store = LocalFileSystem::new_with_prefix(path)
        .map_err(|e| rustler::Error::Term(Box::new(format!("Local FS error: {}", e))))?;

    Ok(ResourceArc::new(StoreWrapper::new(Arc::new(store))))
}

/// Create a new in-memory object store
#[rustler::nif]
pub fn new_memory() -> NifResult<ResourceArc<StoreWrapper>> {
    let store = InMemory::new();
    Ok(ResourceArc::new(StoreWrapper::new(Arc::new(store))))
}
