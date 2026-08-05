/// Compatibility imports for applications migrating from Hokusai 0.x.
///
/// This module intentionally re-exports only the existing adapter surface. It
/// does not provide synchronous wrappers around the 1.0 async terminal API.
/// Migrate new code to `import Hokusai` and the immutable `Hokusai(data:)` or
/// `Hokusai(url:)` pipeline documented in the package README.
@_exported import Hokusai
