; -*- coding: utf-8 -*-
Unicode true
RequestExecutionLevel user
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!include "WordFunc.nsh"
!include "package-config.nsh"

Name "Đồng phục Ngọc Thanh — Chạy thử"
OutFile "${OUTPUT_FILE}"
InstallDir "${INSTALL_ROOT}"
BrandingText "Đồng phục Ngọc Thanh · ${VERSION} · Bản chạy thử"
SetCompressor /SOLID lzma
VIProductVersion "${FILE_VERSION}"
VIAddVersionKey /LANG=1066 "ProductName" "Đồng phục Ngọc Thanh — Chạy thử"
VIAddVersionKey /LANG=1066 "FileDescription" "Bộ cài đặt Đồng phục Ngọc Thanh"
VIAddVersionKey /LANG=1066 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1066 "LegalCopyright" "Đồng phục Ngọc Thanh"
ShowInstDetails show
ShowUninstDetails show
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Cài đặt Đồng phục Ngọc Thanh"
!define MUI_WELCOMEPAGE_TEXT "Bản chạy thử ${VERSION}. Hãy sao lưu trước khi nâng cấp và đóng ứng dụng.$\r$\n$\r$\nCài cho tài khoản Windows hiện tại. Dữ liệu SQLite và bản sao lưu được giữ nguyên khi nâng cấp hoặc gỡ ứng dụng.$\r$\n$\r$\nChỉ dùng dữ liệu thử; cloud chưa được thiết lập tự động."
!define MUI_FINISHPAGE_TEXT "Đã cài bản chạy thử. Mở ứng dụng từ menu Start.$\r$\n$\r$\nLần đầu cần đặt mật khẩu quản trị. Nâng cấp giữ dữ liệu; ứng dụng sao lưu trước khi nâng schema.$\r$\n$\r$\nĐọc Hướng dẫn chạy thử trước khi sử dụng."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!define MUI_UNCONFIRMPAGE_TEXT_TOP "Gỡ các tệp chương trình đã cài. SQLite, hàng đợi đồng bộ, bản sao lưu và tệp khác của bạn được giữ nguyên. Đóng ứng dụng trước khi tiếp tục."
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Vietnamese"

Var SetupMutex

!macro CheckSafeDirectory PATH
  System::Call 'kernel32::GetFileAttributesW(w "${PATH}") i .r0'
  ${If} $0 != -1
    IntOp $0 $0 & 0x400
    ${If} $0 != 0
      IfSilent +2
      MessageBox MB_OK|MB_ICONSTOP "Thư mục cài có liên kết chuyển hướng. Dừng để bảo vệ dữ liệu."
      SetErrorLevel 4
      Quit
    ${EndIf}
  ${EndIf}
!macroend

!macro CheckNotRunning
  IfFileExists "$INSTDIR\ngoc_thanh_pos.exe" 0 no_running_app
  System::Call 'kernel32::CreateFileW(w "$INSTDIR\ngoc_thanh_pos.exe", i 0x40000000, i 7, p 0, i 3, i 0, p 0) p .r0'
  ${If} $0 == -1
    IfSilent +2
    MessageBox MB_OK|MB_ICONSTOP "Ứng dụng đang chạy hoặc tệp bị khóa. Đóng Đồng phục Ngọc Thanh rồi thử lại."
    SetErrorLevel 3
    Quit
  ${EndIf}
  System::Call 'kernel32::CloseHandle(p r0)'
no_running_app:
!macroend

!macro Initialize
  SetShellVarContext current
  SetRegView 64
  ${IfNot} ${RunningX64}
    IfSilent +2
    MessageBox MB_OK|MB_ICONSTOP "Cần Windows 10/11 64-bit."
    SetErrorLevel 2
    Quit
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    IfSilent +2
    MessageBox MB_OK|MB_ICONSTOP "Cần Windows 10/11 64-bit."
    SetErrorLevel 2
    Quit
  ${EndIf}
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\${MUTEX_NAME}") p .r1 ?e'
  Pop $0
  StrCpy $SetupMutex $1
  ${If} $SetupMutex == 0
    SetErrorLevel 5
    Quit
  ${EndIf}
  ${If} $0 == 183
    SetErrorLevel 5
    Quit
  ${EndIf}
!macroend

Function .onInit
  !insertmacro Initialize
  ; Fixed per-user path, including in silent mode: /D cannot redirect writes.
  StrCpy $INSTDIR "${INSTALL_ROOT}"
  !insertmacro CheckSafeDirectory "$INSTDIR"
  !include "check-directories.nsh"
  ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "DisplayVersion"
  ${If} $0 != ""
    ${VersionCompare} "$0" "${VERSION}" $1
    ${If} $1 == 1
      IfSilent +2
      MessageBox MB_OK|MB_ICONSTOP "Đã có bản mới hơn. Không hạ phiên bản để tránh lỗi schema dữ liệu."
      SetErrorLevel 6
      Quit
    ${EndIf}
  ${EndIf}
  !insertmacro CheckNotRunning
FunctionEnd

Section "Ứng dụng" SEC_APP
  SetOverwrite on
  ClearErrors
  !include "install-files.nsh"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  ${If} ${Errors}
    IfSilent +2
    MessageBox MB_OK|MB_ICONSTOP "Không ghi đủ tệp chương trình. Kiểm tra dung lượng/quyền thư mục rồi chạy lại bộ cài."
    SetErrorLevel 1
    Quit
  ${EndIf}
  CreateDirectory "${SHORTCUT_ROOT}"
  CreateShortCut "${SHORTCUT_ROOT}\Đồng phục Ngọc Thanh.lnk" "$INSTDIR\ngoc_thanh_pos.exe"
  CreateShortCut "${SHORTCUT_ROOT}\Hướng dẫn chạy thử.lnk" "$INSTDIR\HUONG-DAN.md"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Đồng phục Ngọc Thanh — Chạy thử"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Đồng phục Ngọc Thanh"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\ngoc_thanh_pos.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Function un.onInit
  !insertmacro Initialize
  StrCmp $INSTDIR "${INSTALL_ROOT}" +3
  SetErrorLevel 4
  Quit
  !insertmacro CheckSafeDirectory "$INSTDIR"
  !include "check-directories.nsh"
  !insertmacro CheckNotRunning
FunctionEnd

Section "Uninstall"
  ; Explicit files only. No recursive deletion; user-created files survive.
  !include "uninstall-files.nsh"
  Delete "${SHORTCUT_ROOT}\Đồng phục Ngọc Thanh.lnk"
  Delete "${SHORTCUT_ROOT}\Hướng dẫn chạy thử.lnk"
  RMDir "${SHORTCUT_ROOT}"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
