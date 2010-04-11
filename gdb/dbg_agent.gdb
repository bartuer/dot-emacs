file /Users/bartuer/local/src/chromium/src/xcodebuild/Debug/Chromium.app/Contents/MacOS/Chromium
# set args --remote-shell-port="8585"
# not called here when launch browser
# b v8::V8::Initialize
# b DebuggerRemoteService::HandleMessage
# b v8::Debug::EnableAgent
# b BrowserInit::LaunchBrowser
# call v8::Debug::EnableAgent("d8 shell", 5858, true)
# #6  0x07fcc5ac in CheckHelper (file=0x9128c6e "../../src/debug-agent.h", line=52, source=0x9128c5a "instance_ == __null", condition=false) at checks.h:62
# abort for v8 has not available
# b BrowserInit::LaunchWithProfile::Launch
# b /Users/bartuer/local/src/chromium/src/chrome/browser/browser_init.cc:472
# set port = 5858
# b BrowserProcessImpl::InitDebuggerWrapper 
# set $port = 5858
# call g_browser_process->InitDebuggerWrapper($port)
# b DevToolsProtocolHandler::Init
# NEW THREAD BEGIN LISTEN NOW:
# [Switching to process 1687 thread 0x4b03]
# DevToolsRemoteListenSocket::Listen (ip=@0xb02a88e8, port=5858, del=0x16fca0, listener=0x16fc90) at /Users/bartuer/local/src/chromium/src/chrome/browser/debugger/devtools_remote_listen_socket.cc:97

# ENTER EVENT LOOP NOW:
#22 0x95912f88 in -[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:] ()
#23 0x9590bf9f in -[NSApplication run] ()
#24 0x07a6f186 in base::MessagePumpNSApplication::DoRun (this=0x145ae0, delegate=0xbfffd834) at /Users/bartuer/local/src/chromium/src/base/message_pump_mac.mm:677
#25 0x07a6f775 in base::MessagePumpCFRunLoopBase::Run (this=0x145ae0, delegate=0xbfffd834) at /Users/bartuer/local/src/chromium/src/base/message_pump_mac.mm:213
#26 0x07aa31e6 in MessageLoop::RunInternal (this=0xbfffd834) at /Users/bartuer/local/src/chromium/src/base/message_loop.cc:205
#27 0x07aa3201 in MessageLoop::RunHandler (this=0xbfffd834) at /Users/bartuer/local/src/chromium/src/base/message_loop.cc:177
#28 0x07aa3265 in MessageLoop::Run (this=0xbfffd834) at /Users/bartuer/local/src/chromium/src/base/message_loop.cc:155
#29 0x073108a1 in (anonymous namespace)::RunUIMessageLoop (browser_process=0x14fc80) at /Users/bartuer/local/src/chromium/src/chrome/browser/browser_main.cc:171
#30 0x073127bb in BrowserMain (parameters=@0xbfffe704) at /Users/bartuer/local/src/chromium/src/chrome/browser/browser_main.cc:1077
#31 0x071700f7 in ChromeMain (argc=3, argv=0xbfffef78) at /Users/bartuer/local/src/chromium/src/chrome/app/chrome_dll_main.cc:807

# hey, the chromium LISTEN THERE M-3 5858:
# COMMAND   PID    USER   FD   TYPE    DEVICE SIZE/OFF NODE NAME
# Chromium 1687 bartuer   29u  IPv4 0x961c270      0t0  TCP localhost:5858 (LISTEN)

# then connect to the service
# socat - TCP4:127.0.0.1:5858 no response
# d8 --remote_debugger
# help could output and no prompt

# kill -s 5 chromium_pid
# then add lots of breakpoint on DevToolsRemoteListenSocket

# read the socket content in DevToolsRemoteListenSocket::DispatchRead
# see the payload line must end with \r
# if (*pBuf == '\r') {
# set pBuf[4]='\r'
# handshake should be "ChromeDevToolsHandshake\r\n"
# header in format, key : value, the message will be delegate to different handler
# destination is just the tab
# payload hold the protocol json?

# b DevToolsRemoteListenSocket::HandleMessage
# call HandleMessage()

# the header format should be
# (link "~/local/src/chromium/src/chrome/browser/debugger/devtools_remote_message.cc" 263)
# (link "~/local/src/chromium/src/chrome/browser/debugger/debugger_remote_service.cc" 2231)

# set $message_builder = DevToolsRemoteMessageBuilder::instance()
# that message blocked by messy c++ syntax, need hand write the protocol message
# b DevToolsRemoteListenSocket::Accept        #connect
# b DevToolsRemoteListenSocket::Read          #recieve 
# b DevToolsRemoteListenSocket::DispatchRead  #handshake
# b DevToolsRemoteListenSocket::DispatchField #parse header
# b DevToolsRemoteListenSocket::HandleMessage #dispatch to right handler

# socat - TCP4:127.0.0.1:5858,crnl
# ChromeDevToolsHandshake
# Tool:V8Debugger
# Destination:2
# Content-Length:20

# {"command":"attach"}
# enter DebuggerRemoteService::HandleMessage

# message not reach v8 debugger
# b DebuggerRemoteService::HandleMessage
# b DebuggerRemoteService::DispatchDebuggerCommand
# b DebuggerRemoteService::AttachToTab
# see the tab_uid, it is 2, strange
# b inspectable_tab_proxy.cc:73;

# report the tool is wrong
b devtools_protocol_handler.cc:70

# fix a bug in (link "~/local/src/chromium/src/chrome/browser/debugger/devtools_remote_listen_socket.cc" 6446)
# the protocol works!
# socat - TCP4:127.0.0.1:5858,crnl
# ChromeDevToolsHandshake
# Tool:V8Debugger
# Destination:2
# Content-Length:20

# {"command":"attach"}
# ChromeDevToolsHandshake
# Destination:2
# Tool:V8Debugger
# Content-Length:31

# {"command":"attach","result":0}
# ChromeDevToolsHandshake
# Tool:V8Debugger
# Destination:2
# Content-Length:20

# {"command":"detach"}
# Destination:2
# Tool:V8Debugger
# Content-Length:31

# {"command":"detach","result":0}
# ChromeDevToolsHandshake
# Tool:V8Debugger
# Destination:2
# Content-Length:20

# {"command":"attach"}
# Destination:2
# Tool:V8Debugger
# Content-Length:31

# {"command":"attach","result":0}
# ChromeDevToolsHandshake
# Tool:V8Debugger
# Destination:2
# Content-Length:86

# {"command":"debugger_command", "data":{"seq":0,"type":"request","command":"continue"}}
# Destination:2
# Tool:V8Debugger
# Content-Length:127

# {"command":"debugger_command","result":0,"data":{"seq":4,"type":"response","command":"continue","success":true,"running":true}}
# b BrowserRenderProcessHost::Send

# rbreak DebuggerAgentImpl::*
# rbreak DebuggerAgentManager::*
# shell: dtruss -t sendmsg -p $(pidof chromium)
# shell: dtruss -t recvmsg -p $(pidof chromium help)
# the reason could not set break point is v8 and webkit debuggeragent run in another process
set follow-fork-mode child
b DebuggerAgentImpl::processDebugCommands
b WebKit::DebuggerAgentManager::sendCommandToV8

# start gdb
shell ps |grep Chromium.*Helper
# attach to help works
# r