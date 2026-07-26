///|
extern "C" fn redirect_stdio_to_devnull_ffi() -> Int = "mcpx_redirect_stdio_to_devnull"

///|
pub fn redirect_stdio_to_devnull() -> Bool {
  redirect_stdio_to_devnull_ffi() == 0
}
