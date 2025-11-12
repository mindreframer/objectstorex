use rustler::{Decoder, Error as RustlerError, NifResult, NifStruct, Term};

/// Elixir representation of PutMode for conditional writes
///
/// Matches Elixir patterns:
/// - :overwrite
/// - :create
/// - {:update, %{etag: ..., version: ...}}
#[derive(Debug, Clone)]
pub enum PutModeNif {
    Overwrite,
    Create,
    Update {
        etag: Option<String>,
        version: Option<String>,
    },
}

/// Elixir representation of GetOptions for conditional reads
///
/// Matches Elixir struct: %ObjectStoreX.GetOptions{}
#[derive(Debug, Clone, NifStruct)]
#[module = "ObjectStoreX.GetOptions"]
pub struct GetOptionsNif {
    /// Only return if ETag matches (HTTP If-Match)
    pub if_match: Option<String>,
    /// Only return if ETag differs (HTTP If-None-Match)
    pub if_none_match: Option<String>,
    /// Only return if modified after date (Unix timestamp in seconds)
    pub if_modified_since: Option<i64>,
    /// Only return if not modified since date (Unix timestamp in seconds)
    pub if_unmodified_since: Option<i64>,
    /// Byte range to fetch
    pub range: Option<RangeNif>,
    /// Specific object version
    pub version: Option<String>,
    /// Return metadata only (no content)
    pub head: bool,
}

/// Elixir representation of a byte range for partial reads
///
/// Matches Elixir struct: %ObjectStoreX.Range{}
#[derive(Debug, Clone, NifStruct)]
#[module = "ObjectStoreX.Range"]
pub struct RangeNif {
    /// Start byte (inclusive)
    pub start: u64,
    /// End byte (exclusive)
    pub end: u64,
}

impl<'a> Decoder<'a> for PutModeNif {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        // Try to decode as atom first
        if let Ok(atom_str) = term.atom_to_string() {
            return match atom_str.as_str() {
                "overwrite" => Ok(PutModeNif::Overwrite),
                "create" => Ok(PutModeNif::Create),
                _ => Err(RustlerError::BadArg),
            };
        }

        // Try to decode as tuple {:update, map}
        let tuple_result: Result<(Term, Term), _> = term.decode();
        if let Ok((tag, map)) = tuple_result {
            if let Ok(tag_str) = tag.atom_to_string() {
                if tag_str == "update" {
                    use rustler::types::map::MapIterator;

                    let mut etag: Option<String> = None;
                    let mut version: Option<String> = None;

                    if let Some(iter) = MapIterator::new(map) {
                        for (key, value) in iter {
                            if let Ok(key_str) = key.atom_to_string() {
                                match key_str.as_str() {
                                    "etag" => {
                                        etag = value.decode().ok();
                                    }
                                    "version" => {
                                        version = value.decode().ok();
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }

                    return Ok(PutModeNif::Update { etag, version });
                }
            }
        }

        Err(RustlerError::BadArg)
    }
}
