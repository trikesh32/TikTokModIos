Upstream: https://github.com/facebook/fishhook
Commit: aadc161ac3b80db07a9908851839a17ba63a9eb1
Files fishhook.c/fishhook.h and LICENSE are unmodified upstream copies.
Used only to observe Security import calls in this app's own images.
No system-framework imports are rebound by the diagnostic module.
Successful rebind_symbols_image() does not prove coverage: a keychain_result
event is required to establish that an observed call reached the wrapper.
