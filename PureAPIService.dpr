program PureAPIService;

{$APPTYPE CONSOLE}

{$IF CompilerVersion > 20}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
  {$WEAKLINKRTTI ON}
{$IFEND}

uses
  Windows,
  WinSvc;

const
  ServiceName     = 'Pure API Service';
  DisplayName     = 'Pure Windows API Service';
  NUM_OF_SERVICES = 2;

var
  ServiceStatus : TServiceStatus;
  StatusHandle  : SERVICE_STATUS_HANDLE;
  ServiceTable  : array [0..NUM_OF_SERVICES] of TServiceTableEntry;
  Stopped       : Boolean;
  Paused        : Boolean;

var
  ghSvcStopEvent: Cardinal;

procedure OnServiceCreate;
begin
  // do your stuff here;
end;

procedure AfterUninstall;
begin
  // do your stuff here;
end;


procedure ReportSvcStatus(dwCurrentState, dwWin32ExitCode, dwWaitHint: DWORD);
begin
  // fill in the SERVICE_STATUS structure.
  ServiceStatus.dwCurrentState := dwCurrentState;
  ServiceStatus.dwWin32ExitCode := dwWin32ExitCode;
  ServiceStatus.dwWaitHint := dwWaitHint;

  case dwCurrentState of
    SERVICE_START_PENDING: ServiceStatus.dwControlsAccepted := 0;
    else
      ServiceStatus.dwControlsAccepted := SERVICE_ACCEPT_STOP;
  end;

  case (dwCurrentState = SERVICE_RUNNING) or (dwCurrentState = SERVICE_STOPPED) of
    True: ServiceStatus.dwCheckPoint := 0;
    False: ServiceStatus.dwCheckPoint := 1;
  end;

  // Report the status of the service to the SCM.
  SetServiceStatus(StatusHandle, ServiceStatus);
end;

procedure MainProc;
begin
  // we have to do something or service will stop
  ghSvcStopEvent := CreateEvent(nil, True, False, nil);

  if ghSvcStopEvent = 0 then
  begin
    ReportSvcStatus(SERVICE_STOPPED, NO_ERROR, 0);
    Exit;
  end;

  // Report running status when initialization is complete.
  ReportSvcStatus( SERVICE_RUNNING, NO_ERROR, 0 );

  // Perform work until service stops.
  while True do
  begin
    // Check whether to stop the service.
    WaitForSingleObject(ghSvcStopEvent, INFINITE);
    ReportSvcStatus(SERVICE_STOPPED, NO_ERROR, 0);
    Exit;
  end;
end;

procedure ServiceCtrlHandler(Control: DWORD); stdcall;
begin
  case Control of
    SERVICE_CONTROL_STOP:
      begin
        Stopped := True;
        SetEvent(ghSvcStopEvent);
        ServiceStatus.dwCurrentState := SERVICE_STOP_PENDING;
        SetServiceStatus(StatusHandle, ServiceStatus);
      end;
    SERVICE_CONTROL_PAUSE:
      begin
        Paused := True;
        ServiceStatus.dwcurrentstate := SERVICE_PAUSED;
        SetServiceStatus(StatusHandle, ServiceStatus);
      end;
    SERVICE_CONTROL_CONTINUE:
      begin
        Paused := False;
        ServiceStatus.dwCurrentState := SERVICE_RUNNING;
        SetServiceStatus(StatusHandle, ServiceStatus);
      end;
    SERVICE_CONTROL_INTERROGATE: SetServiceStatus(StatusHandle, ServiceStatus);
    SERVICE_CONTROL_SHUTDOWN: Stopped := True;
  end;
end;

procedure RegisterService(dwArgc: DWORD; var lpszArgv: PChar); stdcall;
begin
  ServiceStatus.dwServiceType := SERVICE_WIN32_OWN_PROCESS;
  ServiceStatus.dwCurrentState := SERVICE_START_PENDING;
  ServiceStatus.dwControlsAccepted := SERVICE_ACCEPT_STOP or SERVICE_ACCEPT_PAUSE_CONTINUE;
  ServiceStatus.dwServiceSpecificExitCode := 0;
  ServiceStatus.dwWin32ExitCode := 0;
  ServiceStatus.dwCheckPoint := 0;
  ServiceStatus.dwWaitHint := 0;

  StatusHandle := RegisterServiceCtrlHandler(ServiceName, @ServiceCtrlHandler);

  if StatusHandle <> 0 then
  begin
    ReportSvcStatus(SERVICE_RUNNING, NO_ERROR, 0);
    try
      Stopped := False;
      Paused  := False;
      MainProc;
    finally
      ReportSvcStatus(SERVICE_STOPPED, NO_ERROR, 0);
    end;
  end;
end;

procedure UninstallService(const ServiceName: PChar; const Silent: Boolean);
const
  cRemoveMsg = 'Service uninstalled.';
var
  SCManager: SC_HANDLE;
  Service: SC_HANDLE;
begin
  SCManager := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  if SCManager = 0 then
    Exit;
  try
    Service := OpenService(SCManager, ServiceName, SERVICE_ALL_ACCESS);
    ControlService(Service, SERVICE_CONTROL_STOP, ServiceStatus);
    DeleteService(Service);
    CloseServiceHandle(Service);
    if not Silent then
      MessageBox(0, cRemoveMsg, ServiceName, MB_ICONINFORMATION or MB_OK or MB_TASKMODAL or MB_TOPMOST);
  finally
    CloseServiceHandle(SCManager);
    AfterUninstall;
  end;
end;

procedure InstallService(const ServiceName, DisplayName, LoadOrder: PChar;
  const FileName: string; const Silent: Boolean);
const
  cInstallMsg = 'Install successful.';
  cSCMError = 'Install failure.';
var
  SCMHandle  : SC_HANDLE;
  SvHandle   : SC_HANDLE;
begin
  SCMHandle := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);

  if SCMHandle = 0 then
  begin
    MessageBox(0, cSCMError, ServiceName, MB_ICONERROR or MB_OK or MB_TASKMODAL or MB_TOPMOST);
    Exit;
  end;

  try
    SvHandle := CreateService(SCMHandle,
                              ServiceName,
                              DisplayName,
                              SERVICE_ALL_ACCESS,
                              SERVICE_WIN32_OWN_PROCESS,
                              SERVICE_AUTO_START,
                              SERVICE_ERROR_IGNORE,
                              pchar(FileName),
                              LoadOrder,
                              nil,
                              nil,
                              nil,
                              nil);
    CloseServiceHandle(SvHandle);

    if not Silent then
      MessageBox(0, cInstallMsg, ServiceName, MB_ICONINFORMATION or MB_OK or MB_TASKMODAL or MB_TOPMOST);
  finally
    CloseServiceHandle(SCMHandle);
  end;
end;

procedure DoBanner;
begin
  WriteLn('Pure API Service v1.0');
  WriteLn('Copyright (c) 2009 Microsoft Corporation.  All rights reserved.');
  WriteLn('- '+ParamStr(0)+' /install');
  WriteLn('- '+ParamStr(0)+' /remove');
  WriteLn('- '+ParamStr(0)+' /? or /h');
end;

begin
  if (ParamStr(1) = '/h') or (ParamStr(1) = '/?') then
    DoBanner
  else if ParamStr(1) = '/install' then
    InstallService(ServiceName, DisplayName, 'System Reserved', ParamStr(0), ParamStr(2) = '/s')
  else if ParamStr(1) = '/remove' then
    UninstallService(ServiceName, ParamStr(2) = '/s')
  else if ParamCount = 0 then
  begin
    OnServiceCreate;

    ServiceTable[0].lpServiceName := ServiceName;
    ServiceTable[0].lpServiceProc := @RegisterService;
    ServiceTable[1].lpServiceName := nil;
    ServiceTable[1].lpServiceProc := nil;

    StartServiceCtrlDispatcher(ServiceTable[0]);
  end
  else
    WriteLn('Wrong argument!');
end.

