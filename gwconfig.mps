// ===========================================================================
// GWCONFIG.MPS - Mystic BBS MPL Configuration Manager for BBS Telnet Gateway
// ===========================================================================
// Reads and writes the shared, human-readable `gateway.cfg` file used by
// `bbs_gateway.py`. Allows the SysOp (or authorized users) to:
//   - View, Add, Edit, Delete, and Reorder Local & External BBS listings
//   - Configure Gateway Title, Port 23 / Listen Settings, Display Mode
//     (BOTH, LIGHTBAR, ANSI_HOTKEY), Timeouts, and Lightbar Color Attributes
//   - Preview the configured `gateway.ans` screen inside Mystic BBS
//
// COMPILATION:
//   1. Copy `gwconfig.mps` to your Mystic scripts directory
//      (e.g. /mystic/themes/default/scripts/)
//   2. Compile with MPLC:
//      ./mplc gwconfig.mps
//   3. Add to any Mystic menu (usually your SysOp Menu):
//      Menu Command: GX (Execute MPL Program)
//      Command Data: gwconfig /path/to/gateway.cfg
//      Access ACS  : s255 (or your desired SysOp security level)
// ===========================================================================

Uses CFG;
Uses USER;

Const
  MaxBBS       = 50;
  MinSysopSec  = 200; // Minimum security level required to run editor

Type
  TBBSEntry = Record
    Hotkey      : String[2];
    Name        : String[30];
    Host        : String[45];
    Port        : String[8];
    Scope       : String[10]; // LOCAL or EXTERNAL
    Description : String[60];
  End;

Var
  CfgFilePath             : String[160];
  GwTitle                 : String[60];
  SysopName               : String[40];
  ListenHost              : String[40];
  ListenPort              : String[10];
  AnsiFile                : String[80];
  DisplayMode             : String[15];
  MenuStartX              : Byte;
  MenuStartY              : Byte;
  MenuWidth               : Byte;
  MenuRows                : Byte;
  IdleTimeout             : Integer;
  ConnectTimeout          : Integer;
  ReturnAfterDisconnect   : Boolean;
  ColorHeader             : Byte;
  ColorBorder             : Byte;
  ColorItemFG             : Byte;
  ColorItemBG             : Byte;
  ColorHiliteFG           : Byte;
  ColorHiliteBG           : Byte;

  BBSList                 : Array[1..MaxBBS] of TBBSEntry;
  BBSCount                : Byte;
  SelectedIdx             : Byte;
  TopIdx                  : Byte;
  Modified                : Boolean;
  QuitProgram             : Boolean;

// ---------------------------------------------------------------------------
// Initialize default configuration values prior to loading gateway.cfg
// ---------------------------------------------------------------------------
Procedure InitDefaults;
Begin
  GwTitle               := 'The Nexus BBS Telnet Gateway';
  SysopName             := 'SysOp';
  ListenHost            := '0.0.0.0';
  ListenPort            := '23';
  AnsiFile              := 'gateway.ans';
  DisplayMode           := 'BOTH';
  MenuStartX            := 5;
  MenuStartY            := 10;
  MenuWidth             := 72;
  MenuRows              := 8;
  IdleTimeout           := 180;
  ConnectTimeout        := 15;
  ReturnAfterDisconnect := True;
  ColorHeader           := 15;
  ColorBorder           := 11;
  ColorItemFG           := 7;
  ColorItemBG           := 0;
  ColorHiliteFG         := 15;
  ColorHiliteBG         := 1;
  BBSCount              := 0;
  SelectedIdx           := 1;
  TopIdx                := 1;
  Modified              := False;
  QuitProgram           := False;

  If StripB(ProgParams, ' ') <> '' Then
    CfgFilePath := StripB(ProgParams, ' ')
  Else
    CfgFilePath := CfgDataPath + 'gateway.cfg';
End;

// ---------------------------------------------------------------------------
// Helper: Convert Boolean to 'TRUE' / 'FALSE' string for gateway.cfg
// ---------------------------------------------------------------------------
Function BoolToCfg(Val : Boolean) : String;
Begin
  If Val Then
    BoolToCfg := 'TRUE'
  Else
    BoolToCfg := 'FALSE';
End;

// ---------------------------------------------------------------------------
// Helper: Parse Boolean from gateway.cfg text value
// ---------------------------------------------------------------------------
Function CfgToBool(Val : String) : Boolean;
Var
  U : String;
Begin
  U := Upper(StripB(Val, ' '));
  If (U = 'TRUE') Or (U = 'YES') Or (U = '1') Or (U = 'ON') Then
    CfgToBool := True
  Else
    CfgToBool := False;
End;

// ---------------------------------------------------------------------------
// Load human-readable gateway.cfg into memory
// ---------------------------------------------------------------------------
Procedure LoadConfig;
Var
  F       : File;
  Line    : String;
  Trimmed : String;
  EqPos   : Byte;
  Key     : String;
  Val     : String;
Begin
  BBSCount := 0;
  If Not FileExist(CfgFilePath) Then Exit;

  fAssign(F, CfgFilePath, 66);
  fReset(F);
  If IoResult <> 0 Then Exit;

  While Not fEof(F) Do Begin
    fReadLn(F, Line);
    Trimmed := StripB(Line, ' ');

    If (Length(Trimmed) > 0) And (Trimmed[1] <> '#') And (Trimmed[1] <> ';') Then Begin
      EqPos := Pos('=', Trimmed);
      If EqPos > 0 Then Begin
        Key := Upper(StripB(Copy(Trimmed, 1, EqPos - 1), ' '));
        Val := StripB(Copy(Trimmed, EqPos + 1, Length(Trimmed) - EqPos), ' ');

        If Key = 'GATEWAY_TITLE' Then GwTitle := Val
        Else If Key = 'SYSOP_NAME' Then SysopName := Val
        Else If Key = 'LISTEN_HOST' Then ListenHost := Val
        Else If Key = 'LISTEN_PORT' Then ListenPort := Val
        Else If Key = 'ANSI_FILE' Then AnsiFile := Val
        Else If Key = 'DISPLAY_MODE' Then DisplayMode := Upper(Val)
        Else If Key = 'MENU_START_X' Then MenuStartX := Str2Int(Val)
        Else If Key = 'MENU_START_Y' Then MenuStartY := Str2Int(Val)
        Else If Key = 'MENU_WIDTH' Then MenuWidth := Str2Int(Val)
        Else If Key = 'MENU_ROWS' Then MenuRows := Str2Int(Val)
        Else If Key = 'IDLE_TIMEOUT' Then IdleTimeout := Str2Int(Val)
        Else If Key = 'CONNECT_TIMEOUT' Then ConnectTimeout := Str2Int(Val)
        Else If Key = 'RETURN_AFTER_DISCONNECT' Then ReturnAfterDisconnect := CfgToBool(Val)
        Else If Key = 'COLOR_HEADER' Then ColorHeader := Str2Int(Val)
        Else If Key = 'COLOR_BORDER' Then ColorBorder := Str2Int(Val)
        Else If Key = 'COLOR_ITEM_FG' Then ColorItemFG := Str2Int(Val)
        Else If Key = 'COLOR_ITEM_BG' Then ColorItemBG := Str2Int(Val)
        Else If Key = 'COLOR_HILITE_FG' Then ColorHiliteFG := Str2Int(Val)
        Else If Key = 'COLOR_HILITE_BG' Then ColorHiliteBG := Str2Int(Val)
        Else If (Key = 'BBS') And (BBSCount < MaxBBS) Then Begin
          If WordCount(Val, '|') >= 4 Then Begin
            BBSCount := BBSCount + 1;
            BBSList[BBSCount].Hotkey      := Upper(StripB(WordGet(1, Val, '|'), ' '));
            BBSList[BBSCount].Name        := StripB(WordGet(2, Val, '|'), ' ');
            BBSList[BBSCount].Host        := StripB(WordGet(3, Val, '|'), ' ');
            BBSList[BBSCount].Port        := StripB(WordGet(4, Val, '|'), ' ');
            If WordCount(Val, '|') >= 5 Then
              BBSList[BBSCount].Scope := Upper(StripB(WordGet(5, Val, '|'), ' '))
            Else
              BBSList[BBSCount].Scope := 'EXTERNAL';
            If WordCount(Val, '|') >= 6 Then
              BBSList[BBSCount].Description := StripB(WordGet(6, Val, '|'), ' ')
            Else
              BBSList[BBSCount].Description := '';
          End;
        End;
      End;
    End;
  End;

  fClose(F);
  If BBSCount > 0 Then SelectedIdx := 1;
  Modified := False;
End;

// ---------------------------------------------------------------------------
// Save memory configuration back to human-readable gateway.cfg
// ---------------------------------------------------------------------------
Procedure SaveConfig;
Var
  F : File;
  I : Byte;
Begin
  fAssign(F, CfgFilePath, 66);
  fReWrite(F);
  If IoResult <> 0 Then Begin
    GotoXY(1, 24);
    WritePipe('|12|16 [!] Error writing configuration file: ' + CfgFilePath + ' |PA');
    Exit;
  End;

  fWriteLn(F, '# ===========================================================================');
  fWriteLn(F, '# BBS TELNET GATEWAY CONFIGURATION (gateway.cfg)');
  fWriteLn(F, '# Generated by Mystic BBS GWCONFIG.MPS Configuration Utility');
  fWriteLn(F, '# ===========================================================================');
  fWriteLn(F, '');
  fWriteLn(F, '# --- General Gateway Settings ---');
  fWriteLn(F, 'GATEWAY_TITLE = ' + GwTitle);
  fWriteLn(F, 'SYSOP_NAME = ' + SysopName);
  fWriteLn(F, 'LISTEN_HOST = ' + ListenHost);
  fWriteLn(F, 'LISTEN_PORT = ' + ListenPort);
  fWriteLn(F, 'ANSI_FILE = ' + AnsiFile);
  fWriteLn(F, 'DISPLAY_MODE = ' + DisplayMode);
  fWriteLn(F, '');
  fWriteLn(F, '# --- Lightbar Menu Geometry (80x25 terminal coordinates) ---');
  fWriteLn(F, 'MENU_START_X = ' + Int2Str(MenuStartX));
  fWriteLn(F, 'MENU_START_Y = ' + Int2Str(MenuStartY));
  fWriteLn(F, 'MENU_WIDTH = ' + Int2Str(MenuWidth));
  fWriteLn(F, 'MENU_ROWS = ' + Int2Str(MenuRows));
  fWriteLn(F, '');
  fWriteLn(F, '# --- Connection & Session Behavior ---');
  fWriteLn(F, 'IDLE_TIMEOUT = ' + Int2Str(IdleTimeout));
  fWriteLn(F, 'CONNECT_TIMEOUT = ' + Int2Str(ConnectTimeout));
  fWriteLn(F, 'RETURN_AFTER_DISCONNECT = ' + BoolToCfg(ReturnAfterDisconnect));
  fWriteLn(F, '');
  fWriteLn(F, '# --- Lightbar Color Attributes (0-15 FG, 0-7 BG) ---');
  fWriteLn(F, 'COLOR_HEADER = ' + Int2Str(ColorHeader));
  fWriteLn(F, 'COLOR_BORDER = ' + Int2Str(ColorBorder));
  fWriteLn(F, 'COLOR_ITEM_FG = ' + Int2Str(ColorItemFG));
  fWriteLn(F, 'COLOR_ITEM_BG = ' + Int2Str(ColorItemBG));
  fWriteLn(F, 'COLOR_HILITE_FG = ' + Int2Str(ColorHiliteFG));
  fWriteLn(F, 'COLOR_HILITE_BG = ' + Int2Str(ColorHiliteBG));
  fWriteLn(F, '');
  fWriteLn(F, '# ===========================================================================');
  fWriteLn(F, '# BBS DIRECTORY LISTINGS');
  fWriteLn(F, '# Format: BBS = Hotkey | Name | Host/IP | Port | Scope | Description');
  fWriteLn(F, '# ===========================================================================');
  fWriteLn(F, '');

  For I := 1 To BBSCount Do Begin
    fWriteLn(F, 'BBS = ' +
      PadRT(BBSList[I].Hotkey, 2, ' ') + ' | ' +
      PadRT(BBSList[I].Name, 22, ' ') + ' | ' +
      PadRT(BBSList[I].Host, 20, ' ') + ' | ' +
      PadRT(BBSList[I].Port, 5, ' ') + ' | ' +
      PadRT(BBSList[I].Scope, 8, ' ') + ' | ' +
      BBSList[I].Description
    );
  End;

  fClose(F);
  Modified := False;
End;

// ---------------------------------------------------------------------------
// Draw the main Mystic SysOp Gateway Configuration UI
// ---------------------------------------------------------------------------
Procedure DrawMainScreen;
Begin
  ClrScr;
  WriteXYPipe(1, 1, 31, 80, ' |15|17 MYSTIC BBS GATEWAY CONFIGURATION MANAGER (GWCONFIG.MPS) ');
  WriteXYPipe(1, 2, 7, 80, '|08 File: |11' + CfgFilePath + ' |08| Mode: |14' + DisplayMode + ' |08| Port: |10' + ListenHost + ':' + ListenPort);
  WriteXYPipe(1, 3, 11, 80, '|03.==============================================================================.');
  WriteXYPipe(1, 4, 11, 80, '|03| |14Key  BBS System Name          Host / IP Address       Port   Scope           |03|');
  WriteXYPipe(1, 5, 11, 80, '|03+------------------------------------------------------------------------------+');

  WriteXYPipe(1, 16, 11, 80, '|03+------------------------------------------------------------------------------+');
  WriteXYPipe(1, 17, 7,  80, '|03| |08Desc:                                                                        |03|');
  WriteXYPipe(1, 18, 11, 80, '|03+==============================================================================+');
  WriteXYPipe(1, 19, 7,  80, '|03| |15[A]|07dd BBS   |15[E]|07dit BBS   |15[D]|07elete BBS   |15[U/N]|07 Move Up/Dn   |15[O]|07ptions & Colors |03|');
  WriteXYPipe(1, 20, 7,  80, '|03| |15[V]|07iew ANSI |15[P]|07ath Cfg   |15[S]|07ave File    |15[Q]|07uit to BBS                        |03|');
  WriteXYPipe(1, 21, 11, 80, '|03`==============================================================================''');
End;

// ---------------------------------------------------------------------------
// Refresh the scrollable list of BBS entries on rows 6..15
// ---------------------------------------------------------------------------
Procedure DrawBBSList;
Var
  Row      : Byte;
  Idx      : Byte;
  Attr     : Byte;
  LineText : String;
Begin
  If SelectedIdx < TopIdx Then TopIdx := SelectedIdx;
  If SelectedIdx >= TopIdx + 10 Then TopIdx := SelectedIdx - 9;
  If TopIdx < 1 Then TopIdx := 1;

  For Row := 0 To 9 Do Begin
    Idx := TopIdx + Row;
    If Idx <= BBSCount Then Begin
      If Idx = SelectedIdx Then
        Attr := ColorHiliteFG + (ColorHiliteBG * 16)
      Else
        Attr := 7;

      LineText := ' [' + PadRT(BBSList[Idx].Hotkey, 1, ' ') + ']  ' +
                  PadRT(BBSList[Idx].Name, 23, ' ') + '  ' +
                  PadRT(BBSList[Idx].Host, 22, ' ') + '  ' +
                  PadRT(BBSList[Idx].Port, 5, ' ') + '  ' +
                  PadRT(BBSList[Idx].Scope, 14, ' ');
      WriteXY(3, 6 + Row, Attr, PadRT(LineText, 76, ' '));
    End Else Begin
      WriteXY(3, 6 + Row, 7, PadRT('', 76, ' '));
    End;
  End;

  If (BBSCount > 0) And (SelectedIdx <= BBSCount) Then
    WriteXY(9, 17, 11, PadRT(BBSList[SelectedIdx].Description, 70, ' '))
  Else
    WriteXY(9, 17, 8, PadRT('No BBS entries configured. Press [A] to add one.', 70, ' '));

  WriteXYPipe(1, 2, 7, 80, '|08 File: |11' + PadRT(CfgFilePath, 34, ' ') + '|08 Mode: |14' + PadRT(DisplayMode, 11, ' ') + '|08 Port: |10' + ListenPort);
End;

// ---------------------------------------------------------------------------
// Edit or Add a BBS Listing Entry
// ---------------------------------------------------------------------------
Procedure EditBBSEntry(Idx : Byte; IsNew : Boolean);
Var
  ScopeChoice : Char;
Begin
  ClrScr;
  WriteXYPipe(1, 1, 31, 80, ' |15|17 EDITING BBS DIRECTORY LISTING #' + Int2Str(Idx) + ' ');

  GotoXY(3, 4);
  WritePipe('|11Hotkey (1-9, A-Z)        : |15');
  BBSList[Idx].Hotkey := Upper(Input(2, 2, 11, BBSList[Idx].Hotkey));

  GotoXY(3, 6);
  WritePipe('|11BBS System Name          : |15');
  BBSList[Idx].Name := Input(30, 30, 11, BBSList[Idx].Name);

  GotoXY(3, 8);
  WritePipe('|11Host / IP Address        : |15');
  WritePipeLn('|08(e.g. 127.0.0.1 for local node or bbs.example.com)');
  GotoXY(30, 8);
  BBSList[Idx].Host := Input(40, 45, 11, BBSList[Idx].Host);

  GotoXY(3, 10);
  WritePipe('|11Telnet Port              : |15');
  BBSList[Idx].Port := Input(6, 6, 20, BBSList[Idx].Port);
  If StripB(BBSList[Idx].Port, ' ') = '' Then BBSList[Idx].Port := '23';

  GotoXY(3, 12);
  WritePipe('|11Connection Scope         : |15[L]|07ocal Address  or  |15[E]|07xternal Host? ');
  ScopeChoice := OneKey('LE' + #13, False);
  If ScopeChoice = 'L' Then
    BBSList[Idx].Scope := 'LOCAL'
  Else If ScopeChoice = 'E' Then
    BBSList[Idx].Scope := 'EXTERNAL';
  WritePipeLn('|14' + BBSList[Idx].Scope);

  GotoXY(3, 14);
  WritePipe('|11Short Description        : |15');
  BBSList[Idx].Description := Input(48, 60, 11, BBSList[Idx].Description);

  Modified := True;
  DrawMainScreen;
  DrawBBSList;
End;

// ---------------------------------------------------------------------------
// Add a new BBS entry to the list
// ---------------------------------------------------------------------------
Procedure AddBBSEntry;
Begin
  If BBSCount >= MaxBBS Then Begin
    GotoXY(1, 23);
    WritePipe('|12Maximum number of BBS listings reached! |PA');
    Exit;
  End;

  BBSCount := BBSCount + 1;
  SelectedIdx := BBSCount;
  If BBSCount <= 9 Then
    BBSList[BBSCount].Hotkey := Int2Str(BBSCount)
  Else
    BBSList[BBSCount].Hotkey := Chr(55 + BBSCount);

  BBSList[BBSCount].Name        := 'New BBS Node';
  BBSList[BBSCount].Host        := '127.0.0.1';
  BBSList[BBSCount].Port        := '2323';
  BBSList[BBSCount].Scope       := 'LOCAL';
  BBSList[BBSCount].Description := 'Local BBS Node';

  EditBBSEntry(BBSCount, True);
End;

// ---------------------------------------------------------------------------
// Delete the currently highlighted BBS entry
// ---------------------------------------------------------------------------
Procedure DeleteBBSEntry;
Var
  I : Byte;
Begin
  If BBSCount = 0 Then Exit;
  GotoXY(3, 23);
  If InputYN('|12Delete "' + BBSList[SelectedIdx].Name + '" from gateway? |15') Then Begin
    For I := SelectedIdx To BBSCount - 1 Do
      BBSList[I] := BBSList[I + 1];
    BBSCount := BBSCount - 1;
    If (SelectedIdx > BBSCount) And (BBSCount > 0) Then
      SelectedIdx := BBSCount;
    Modified := True;
  End;
  DrawMainScreen;
  DrawBBSList;
End;

// ---------------------------------------------------------------------------
// Swap two BBS entries to reorder the lightbar menu
// ---------------------------------------------------------------------------
Procedure SwapBBSEntries(Idx1, Idx2 : Byte);
Var
  Temp : TBBSEntry;
Begin
  Temp          := BBSList[Idx1];
  BBSList[Idx1] := BBSList[Idx2];
  BBSList[Idx2] := Temp;
  Modified      := True;
End;

// ---------------------------------------------------------------------------
// Gateway Options & Lightbar Color Editor Submenu
// ---------------------------------------------------------------------------
Procedure EditGatewayOptions;
Var
  OptKey  : Char;
  DoneOpt : Boolean;
  TmpStr  : String;
Begin
  DoneOpt := False;
  Repeat
    ClrScr;
    WriteXYPipe(1, 1, 31, 80, ' |15|17 GATEWAY SERVER OPTIONS & LIGHTBAR APPEARANCE ');
    GotoXY(1, 3);
    WritePipeLn(' |15[1]|07 Gateway Title            : |11' + GwTitle);
    WritePipeLn(' |15[2]|07 SysOp Name               : |11' + SysopName);
    WritePipeLn(' |15[3]|07 Listen Address           : |11' + ListenHost);
    WritePipeLn(' |15[4]|07 Listen Telnet Port       : |11' + ListenPort);
    WritePipeLn(' |15[5]|07 ANSI Art File            : |11' + AnsiFile);
    WritePipeLn(' |15[6]|07 Display Mode (Toggle)    : |14' + DisplayMode + ' |08(BOTH / LIGHTBAR / ANSI_HOTKEY)');
    WritePipeLn(' |15[7]|07 Lightbar Start X / Y     : |11X=' + Int2Str(MenuStartX) + ', Y=' + Int2Str(MenuStartY) + ', Width=' + Int2Str(MenuWidth) + ', Rows=' + Int2Str(MenuRows));
    WritePipeLn(' |15[8]|07 Idle / Connect Timeouts  : |11Idle=' + Int2Str(IdleTimeout) + 's, Connect=' + Int2Str(ConnectTimeout) + 's');
    WritePipeLn(' |15[9]|07 Return After Disconnect  : |14' + BoolToCfg(ReturnAfterDisconnect));
    WritePipeLn(' |15[C]|07 Lightbar Colors (FG/BG)  : |11Item(' + Int2Str(ColorItemFG) + '/' + Int2Str(ColorItemBG) + ')  Hilite(' + Int2Str(ColorHiliteFG) + '/' + Int2Str(ColorHiliteBG) + ')  Border(' + Int2Str(ColorBorder) + ')');
    WritePipeLn('');
    WritePipe(' |09Select Option |01[|151-9, C|01]|09 or |01[|15Q|01]|09 Return to Listings: |15');

    OptKey := OneKey('123456789CQ' + #27, False);
    Case OptKey Of
      '1': Begin
             GotoXY(3, 16);
             WritePipe('|11New Gateway Title: ');
             GwTitle := Input(45, 60, 11, GwTitle);
             Modified := True;
           End;
      '2': Begin
             GotoXY(3, 16);
             WritePipe('|11SysOp Name: ');
             SysopName := Input(30, 40, 11, SysopName);
             Modified := True;
           End;
      '3': Begin
             GotoXY(3, 16);
             WritePipe('|11Listen Host IP (0.0.0.0 for all): ');
             ListenHost := Input(25, 40, 11, ListenHost);
             Modified := True;
           End;
      '4': Begin
             GotoXY(3, 16);
             WritePipe('|11Listen Telnet Port (default 23): ');
             ListenPort := Input(6, 6, 20, ListenPort);
             Modified := True;
           End;
      '5': Begin
             GotoXY(3, 16);
             WritePipe('|11ANSI Filename (e.g. gateway.ans): ');
             AnsiFile := Input(40, 80, 11, AnsiFile);
             Modified := True;
           End;
      '6': Begin
             If DisplayMode = 'BOTH' Then DisplayMode := 'LIGHTBAR'
             Else If DisplayMode = 'LIGHTBAR' Then DisplayMode := 'ANSI_HOTKEY'
             Else DisplayMode := 'BOTH';
             Modified := True;
           End;
      '7': Begin
             GotoXY(3, 16);
             WritePipe('|11Lightbar Start X (1-40)  : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuStartX));
             MenuStartX := Str2Int(TmpStr);
             GotoXY(3, 17);
             WritePipe('|11Lightbar Start Y (1-20)  : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuStartY));
             MenuStartY := Str2Int(TmpStr);
             GotoXY(3, 18);
             WritePipe('|11Lightbar Width (40-78)   : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuWidth));
             MenuWidth := Str2Int(TmpStr);
             GotoXY(3, 19);
             WritePipe('|11Visible Rows (3-15)      : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuRows));
             MenuRows := Str2Int(TmpStr);
             Modified := True;
           End;
      '8': Begin
             GotoXY(3, 16);
             WritePipe('|11Idle Timeout (seconds)   : ');
             TmpStr := Input(6, 6, 20, Int2Str(IdleTimeout));
             IdleTimeout := Str2Int(TmpStr);
             GotoXY(3, 17);
             WritePipe('|11Connect Timeout (seconds): ');
             TmpStr := Input(6, 6, 20, Int2Str(ConnectTimeout));
             ConnectTimeout := Str2Int(TmpStr);
             Modified := True;
           End;
      '9': Begin
             ReturnAfterDisconnect := Not ReturnAfterDisconnect;
             Modified := True;
           End;
      'C': Begin
             GotoXY(3, 16);
             WritePipe('|11Normal Item FG (0-15)    : ');
             ColorItemFG := Str2Int(Input(3, 3, 20, Int2Str(ColorItemFG)));
             GotoXY(3, 17);
             WritePipe('|11Normal Item BG (0-7)     : ');
             ColorItemBG := Str2Int(Input(3, 3, 20, Int2Str(ColorItemBG)));
             GotoXY(3, 18);
             WritePipe('|11Highlight Bar FG (0-15)  : ');
             ColorHiliteFG := Str2Int(Input(3, 3, 20, Int2Str(ColorHiliteFG)));
             GotoXY(3, 19);
             WritePipe('|11Highlight Bar BG (0-7)   : ');
             ColorHiliteBG := Str2Int(Input(3, 3, 20, Int2Str(ColorHiliteBG)));
             GotoXY(3, 20);
             WritePipe('|11Frame Border FG (0-15)   : ');
             ColorBorder := Str2Int(Input(3, 3, 20, Int2Str(ColorBorder)));
             Modified := True;
           End;
      'Q', #27: DoneOpt := True;
    End;
  Until DoneOpt;

  DrawMainScreen;
  DrawBBSList;
End;

// ---------------------------------------------------------------------------
// Main Program Entry Point
// ---------------------------------------------------------------------------
Var
  Ch : Char;
Begin
  GetThisUser;
  If UserSec < MinSysopSec Then Begin
    WritePipeLn('|CR|12Access Denied: SysOp security level required to configure BBS Gateway.|CR|PA');
    Halt;
  End;

  InitDefaults;
  LoadConfig;
  AllowArrow := True;

  DrawMainScreen;
  DrawBBSList;

  Repeat
    Ch := ReadKey;
    If IsArrow Then Begin
      Case Ch Of
        #72: If SelectedIdx > 1 Then Begin // Up Arrow
               SelectedIdx := SelectedIdx - 1;
               DrawBBSList;
             End;
        #80: If SelectedIdx < BBSCount Then Begin // Down Arrow
               SelectedIdx := SelectedIdx + 1;
               DrawBBSList;
             End;
        #71: Begin // Home
               SelectedIdx := 1;
               DrawBBSList;
             End;
        #79: If BBSCount > 0 Then Begin // End
               SelectedIdx := BBSCount;
               DrawBBSList;
             End;
      End;
    End Else Begin
      Ch := Upper(Ch);
      Case Ch Of
        'A': AddBBSEntry;
        'E', #13: If BBSCount > 0 Then EditBBSEntry(SelectedIdx, False);
        'D': DeleteBBSEntry;
        'U': If SelectedIdx > 1 Then Begin
               SwapBBSEntries(SelectedIdx, SelectedIdx - 1);
               SelectedIdx := SelectedIdx - 1;
               DrawBBSList;
             End;
        'N': If SelectedIdx < BBSCount Then Begin
               SwapBBSEntries(SelectedIdx, SelectedIdx + 1);
               SelectedIdx := SelectedIdx + 1;
               DrawBBSList;
             End;
        'O': EditGatewayOptions;
        'V': Begin
               ClrScr;
               If Not DispFile(AnsiFile) Then
                 WritePipeLn('|12Could not locate ANSI file: ' + AnsiFile);
               GotoXY(1, 24);
               WritePipe('|07Press any key to return to Gateway Config... |PA');
               DrawMainScreen;
               DrawBBSList;
             End;
        'P': Begin
               GotoXY(3, 23);
               WritePipe('|11Path to gateway.cfg: ');
               CfgFilePath := Input(50, 120, 11, CfgFilePath);
               LoadConfig;
               DrawMainScreen;
               DrawBBSList;
             End;
        'S': Begin
               SaveConfig;
               GotoXY(3, 23);
               WritePipe('|10Configuration saved to ' + CfgFilePath + '! |PA');
               DrawMainScreen;
               DrawBBSList;
             End;
        'Q', #27: Begin
               If Modified Then Begin
                 GotoXY(3, 23);
                 If InputYN('|14Save unsaved changes to gateway.cfg before exiting? |15') Then
                   SaveConfig;
               End;
               QuitProgram := True;
             End;
      End;
    End;
  Until QuitProgram;

  AllowArrow := False;
  ClrScr;
End.
