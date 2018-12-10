unit TaskDialog;

{
  Inno Setup
  Copyright (C) 1997-2018 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  TaskDialogMsgBox function integrating with CmnFunc's MsgBox functions
}

interface

uses
  CmnFunc;

function TaskDialogMsgBox(const Instruction, TaskDialogText, MsgBoxText, Caption: String; const Typ: TMsgBoxType; const Buttons: Cardinal; const ButtonLabels: array of String; const ShieldButton: Integer; const ForceMsgBox: Boolean): Integer;

implementation

uses
  Windows, Classes, StrUtils, Math, Forms, Dialogs, SysUtils, Commctrl, CmnFunc2, InstFunc, PathFunc;

var
  TaskDialogIndirectFunc: function(const pTaskConfig: TTaskDialogConfig;
    pnButton: PInteger; pnRadioButton: PInteger;
    pfVerificationFlagChecked: PBOOL): HRESULT; stdcall;

function ShieldButtonCallback(hwnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM; lpRefData: LONG_PTR): HResult; stdcall;
begin
  if (msg = TDN_CREATED) and (lpRefData <> 0) then
    SendMessage(hwnd, TDM_SET_BUTTON_ELEVATION_REQUIRED_STATE, lpRefData, 1);
  Result := S_OK;
end;


function DoTaskDialog(const hWnd: HWND; const Instruction, Text, Caption, Icon: PWideChar; const CommonButtons: Cardinal; const ButtonLabels: array of String; const ButtonIDs: array of Integer; const ShieldButton: Integer; const RightToLeft: Boolean; const TriggerMessageBoxCallbackFuncFlags: LongInt; var ModalResult: Integer): Boolean;
var
  Config: TTaskDialogConfig;
  NButtonLabelsAvailable: Integer;
  ButtonItems: TTaskDialogButtons;
  ButtonItem: TTaskDialogButtonItem;
  I: Integer;
  ActiveWindow: Windows.HWND;
  WindowList: Pointer;
begin
  if Assigned(TaskDialogIndirectFunc) then begin
    try
      ZeroMemory(@Config, Sizeof(Config));
      Config.cbSize := SizeOf(Config);
      if RightToLeft then
        Config.dwFlags := Config.dwFlags or TDF_RTL_LAYOUT;
      { If the application window isn't currently visible, show the task dialog
        with no owner window so it'll get a taskbar button } 
      if IsIconic(Application.Handle) or
         (GetWindowLong(Application.Handle, GWL_STYLE) and WS_VISIBLE = 0) or
         (GetWindowLong(Application.Handle, GWL_EXSTYLE) and WS_EX_TOOLWINDOW <> 0) then
        Config.hWndParent := 0
      else
        Config.hwndParent := hWnd;
      Config.dwCommonButtons := CommonButtons;
      Config.pszWindowTitle := Caption;
      Config.pszMainIcon := Icon;
      Config.pszMainInstruction := Instruction;
      Config.pszContent := Text;
      if ShieldButton <> 0 then begin
        Config.pfCallback := ShieldButtonCallback;
        Config.lpCallbackData := ShieldButton;
      end;
      ButtonItems := nil;
      try
        NButtonLabelsAvailable := Length(ButtonLabels);
        if NButtonLabelsAvailable <> 0 then begin
          ButtonItems := TTaskDialogButtons.Create(nil, TTaskDialogButtonItem);
          Config.dwFlags := Config.dwFlags or TDF_USE_COMMAND_LINKS;
          for I := 0 to NButtonLabelsAvailable-1 do begin
            ButtonItem := TTaskDialogButtonItem(ButtonItems.Add);
            ButtonItem.Caption := ButtonLabels[I];
            ButtonItem.ModalResult := ButtonIDs[I];
          end;
          Config.pButtons := ButtonItems.Buttons;
          Config.cButtons := ButtonItems.Count;
        end;
        TriggerMessageBoxCallbackFunc(TriggerMessageBoxCallbackFuncFlags, False);
        ActiveWindow := GetActiveWindow;
        WindowList := DisableTaskWindows(0);
        try
          Result := TaskDialogIndirectFunc(Config, @ModalResult, nil, nil) = S_OK;
        finally
          EnableTaskWindows(WindowList);
          SetActiveWindow(ActiveWindow);
          TriggerMessageBoxCallbackFunc(TriggerMessageBoxCallbackFuncFlags, True);
        end;
      finally
        ButtonItems.Free;
      end;
    except
      Result := False;
    end;
  end else
    Result := False;
end;

function TaskDialogMsgBox(const Instruction, TaskDialogText, MsgBoxText, Caption: String; const Typ: TMsgBoxType; const Buttons: Cardinal; const ButtonLabels: array of String; const ShieldButton: Integer; const ForceMsgBox: Boolean): Integer;
var
  Icon: PChar;
  TDCommonButtons: Cardinal;
  NButtonLabelsAvailable: Integer;
  ButtonIDs: array of Integer;
begin
  case Typ of
    mbInformation: Icon := TD_INFORMATION_ICON;
    mbError: Icon := TD_WARNING_ICON;
    mbCriticalError: Icon := TD_ERROR_ICON;
  else
    Icon := nil; { No other TD_ constant available, MS recommends to use no icon for questions now and the old icon should only be used for help entries }
  end;
  NButtonLabelsAvailable := Length(ButtonLabels);
  case Buttons of
  //MB_DEFBUTTON1, MB_DEFBUTTON2, MB_DEFBUTTON3, MB_SETFOREGROUND
    MB_OK, MB_OKCANCEL:
      begin
        if NButtonLabelsAvailable = 0 then
          TDCommonButtons := TDCBF_OK_BUTTON
        else begin
          TDCommonButtons := 0;
          ButtonIDs := [IDOK];
        end;
        if Buttons = MB_OKCANCEL then
          TDCommonButtons := TDCommonButtons or TDCBF_CANCEL_BUTTON;
      end;
    MB_YESNO, MB_YESNOCANCEL:
      begin
        if NButtonLabelsAvailable = 0 then
          TDCommonButtons := TDCBF_YES_BUTTON or TDCBF_NO_BUTTON
        else begin
          TDCommonButtons := 0;
          ButtonIDs := [IDYES, IDNO];
        end;
        if Buttons = MB_YESNOCANCEL then
          TDCommonButtons := TDCommonButtons or TDCBF_CANCEL_BUTTON;
      end;
    //MB_ABORTRETRYIGNORE: TDCBF_ABORT_BUTTON and TDCBF_IGNORE_BUTTON don't exist
    MB_RETRYCANCEL:
      begin
        if NButtonLabelsAvailable = 0 then
          TDCommonButtons := TDCBF_RETRY_BUTTON
        else begin
          TDCommonButtons := 0;
          ButtonIDs := [IDRETRY];
        end;
        TDCommonButtons := TDCommonButtons or TDCBF_CANCEL_BUTTON;
      end;
    else
      begin
        InternalError('TaskDialogMsgBox: Invalid Buttons');
        TDCommonButtons := 0; { Silence compiler }
      end;
  end;
  if Length(ButtonIDs) <> NButtonLabelsAvailable then
    InternalError('TaskDialogMsgBox: Invalid ButtonLabels');
  if ForceMsgBox or
     not DoTaskDialog(Application.Handle, PChar(Instruction), PChar(TaskDialogText),
           GetMessageBoxCaption(PChar(Caption), Typ), Icon, TDCommonButtons, ButtonLabels, ButtonIDs, ShieldButton,
           GetMessageBoxRightToLeft, IfThen(Typ = mbCriticalError, MB_ICONSTOP, 0), Result) then
    Result := MsgBox(MsgBoxText, IfThen(Instruction <> '', Instruction, Caption), Typ, Buttons);
end;

procedure InitCommonControls; external comctl32 name 'InitCommonControls';

initialization
  InitCommonControls;
  TaskDialogIndirectFunc := GetProcAddress(GetModuleHandle(comctl32), 'TaskDialogIndirect');

end.
