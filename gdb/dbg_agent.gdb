file /Users/bartuer/local/src/chromium/src/xcodebuild/Debug/Chromium.app/Contents/MacOS/Chromium
set args --remote-shell-port 5858
# not called here when launch browser
# b v8::V8::Initialize
b DebuggerRemoteService::HandleMessage
b v8::Debug::EnableAgent
# b BrowserInit::LaunchBrowser
# call v8::Debug::EnableAgent("d8 shell", 5858, true)
# #6  0x07fcc5ac in CheckHelper (file=0x9128c6e "../../src/debug-agent.h", line=52, source=0x9128c5a "instance_ == __null", condition=false) at checks.h:62
# abort for v8 has not available
b BrowserInit::LaunchWithProfile::Launch
b BrowserProcessImpl::InitDebuggerWrapper 
# set $port = 5858
# call g_browser_process->InitDebuggerWrapper($port)
r
