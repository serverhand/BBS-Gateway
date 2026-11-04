// ===========================================================================
// GWCONFIG.MPS - Mystic BBS MPL Configuration Manager for Telnet/SSH Gateway
// ===========================================================================
// Designed for Mystic BBS CP437 & UTF-8 codecs:
//   - Configures both Telnet (LOCAL / EXTERNAL) and SSH (SSH-LOC / SSH-EXT)
//     BBS directory entries, plus Inbound SSH Server settings
//   - Uses Pascal #nnn CP437 character constants (#201, #205, #187, #186, etc.)
//     so MPLC compiles pure CP437 box-drawing graphics without UTF-8 garbling
//   - Restricts all lines to 79 columns to prevent 80-column terminal wrap
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
    Scope       : String[10]; // LOCAL, EXTERNAL, SSH-LOC, or SSH-EXT
    Description : String[60];
  End;

Var
  CfgFilePath             : String[160];
  GwTitle                 : String[60];
  SysopName               : String[40];
  ListenHost              : String[40];
  ListenPort              : String[10];
  AnsiFile                : String[80];
  SshEnabled              : Boolean;
  SshListenPort           : String[10];
  SshHostKey              : String[80];
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
  GwTitle               := 'The Nexus BBS Telnet & SSH Gateway';
  SysopName             := 'SysOp';
  ListenHost            := '0.0.0.0';
  ListenPort            := '23';
  AnsiFile              := 'gateway.ans';
  SshEnabled            := False;
  SshListenPort         := '2222';
  SshHostKey            := 'gateway_ssh_host_key';
  DisplayMode           := 'BOTH';
  MenuStartX            := 3;
  MenuStartY            := 7;
  MenuWidth             := 75;
  MenuRows              := 10;
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

Function RepChar(Ch : Char; Count : Byte) : String;
Var
  I : Byte;
  S : String;
Begin
  S := '';
  For I := 1 To Count Do
    S := S + Ch;
  RepChar := S;
End;

Function BoolToCfg(Val : Boolean) : String;
Begin
  If Val Then
    BoolToCfg := 'TRUE'
  Else
    BoolToCfg := 'FALSE';
End;

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
        Else If Key = 'SSH_ENABLED' Then SshEnabled := CfgToBool(Val)
        Else If Key = 'SSH_LISTEN_PORT' Then SshListenPort := Val
        Else If Key = 'SSH_HOST_KEY' Then SshHostKey := Val
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
    GotoXY(1, 23);
    WritePipe('|12|16 [!] Error writing configuration file: ' + CfgFilePath + ' |PA');
    Exit;
  End;

  fWriteLn(F, '# ===========================================================================');
  fWriteLn(F, '# BBS TELNET & SSH GATEWAY CONFIGURATION (gateway.cfg)');
  fWriteLn(F, '# Generated by Mystic BBS GWCONFIG.MPS Configuration Utility');
  fWriteLn(F, '# ===========================================================================');
  fWriteLn(F, '');
  fWriteLn(F, '# --- General Gateway Settings ---');
  fWriteLn(F, 'GATEWAY_TITLE = ' + GwTitle);
  fWriteLn(F, 'SYSOP_NAME = ' + SysopName);
  fWriteLn(F, 'LISTEN_HOST = ' + ListenHost);
  fWriteLn(F, 'LISTEN_PORT = ' + ListenPort);
  fWriteLn(F, 'ANSI_FILE = ' + AnsiFile);
  fWriteLn(F, '');
  fWriteLn(F, '# --- Optional Inbound SSH Server Settings ---');
  fWriteLn(F, 'SSH_ENABLED = ' + BoolToCfg(SshEnabled));
  fWriteLn(F, 'SSH_LISTEN_PORT = ' + SshListenPort);
  fWriteLn(F, 'SSH_HOST_KEY = ' + SshHostKey);
  fWriteLn(F, 'DISPLAY_MODE = ' + DisplayMode);
  fWriteLn(F, '');
  fWriteLn(F, '# --- Lightbar Menu Geometry (79-col safe ANSI-BBS coordinates) ---');
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
  fWriteLn(F, '# BBS DIRECTORY LISTINGS (TELNET & SSH)');
  fWriteLn(F, '# Modes: LOCAL, EXTERNAL, SSH-LOC, SSH-EXT');
  fWriteLn(F, '# Format: BBS = Hotkey | Name | Host/IP | Port | Mode | Description');
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
Var
  R : Byte;
Begin
  ClrScr;
  WriteXYPipe(1, 1, 31, 79, ' |15|17 MYSTIC BBS TELNET & SSH GATEWAY CONFIGURATION (GWCONFIG.MPS)');
  WriteXYPipe(1, 2, 7, 79, ' |08File: |11' + PadRT(CfgFilePath, 30, ' ') + '|08Mode: |14' + PadRT(DisplayMode, 10, ' ') + '|08Telnet: |10' + ListenPort + ' |08SSH: |10' + SshListenPort);

  WriteXY(1, 3, 11, #201 + RepChar(#205, 77) + #187);
  WriteXYPipe(1, 4, 11, 79, '|11' + #186 + ' |14Key  BBS System Name          Host / IP Address        Port    Mode         |11' + #186);
  WriteXY(1, 5, 11, #199 + RepChar(#196, 77) + #182);

  For R := 6 To 15 Do
    WriteXY(1, R, 11, #186 + RepChar(' ', 77) + #186);

  WriteXY(1, 16, 11, #199 + RepChar(#196, 77) + #182);
  WriteXYPipe(1, 17, 11, 79, '|11' + #186 + ' |08Desc:                                                                       |11' + #186);
  WriteXY(1, 18, 11, #204 + RepChar(#205, 77) + #185);
  WriteXYPipe(1, 19, 11, 79, '|11' + #186 + ' |15[A]|07dd BBS   |15[E]|07dit BBS   |15[D]|07elete BBS   |15[U/N]|07 Move Up/Dn   |15[O]|07ptions & SSH   |11' + #186);
  WriteXYPipe(1, 20, 11, 79, '|11' + #186 + ' |15[V]|07iew ANSI |15[P]|07ath Cfg   |15[S]|07ave File    |15[Q]|07uit to BBS                       |11' + #186);
  WriteXY(1, 21, 11, #200 + RepChar(#205, 77) + #188);
End;

// ---------------------------------------------------------------------------
// Refresh the scrollable list of BBS entries on rows 6..15
// ---------------------------------------------------------------------------
Procedure DrawBBSList;
Var
  Row      : Byte;
  Idx      : Byte;
  Attr     : Byte;
  Marker   : Char;
  LineText : String;
Begin
  If SelectedIdx < TopIdx Then TopIdx := SelectedIdx;
  If SelectedIdx >= TopIdx + 10 Then TopIdx := SelectedIdx - 9;
  If TopIdx < 1 Then TopIdx := 1;

  For Row := 0 To 9 Do Begin
    Idx := TopIdx + Row;
    If Idx <= BBSCount Then Begin
      If Idx = SelectedIdx Then Begin
        Attr   := ColorHiliteFG + (ColorHiliteBG * 16);
        Marker := #175; // CP437 » pointer
      End Else Begin
        Attr   := 7;
        Marker := ' ';
      End;

      LineText := ' ' + Marker + '[' + PadRT(BBSList[Idx].Hotkey, 1, ' ') + ']  ' +
                  PadRT(BBSList[Idx].Name, 23, ' ') + '  ' +
                  PadRT(BBSList[Idx].Host, 23, ' ') + '  ' +
                  PadRT(BBSList[Idx].Port, 6, ' ') + '  ' +
                  PadRT(BBSList[Idx].Scope, 12, ' ');
      WriteXY(3, 6 + Row, Attr, PadRT(LineText, 75, ' '));
    End Else Begin
      WriteXY(3, 6 + Row, 7, RepChar(' ', 75));
    End;
  End;

  If (BBSCount > 0) And (SelectedIdx <= BBSCount) Then
    WriteXY(9, 17, 11, PadRT(BBSList[SelectedIdx].Description, 69, ' '))
  Else
    WriteXY(9, 17, 8, PadRT('No BBS entries configured. Press [A] to add one.', 69, ' '));

  WriteXYPipe(1, 2, 7, 79, ' |08File: |11' + PadRT(CfgFilePath, 30, ' ') + '|08Mode: |14' + PadRT(DisplayMode, 10, ' ') + '|08Telnet: |10' + ListenPort + ' |08SSH: |10' + SshListenPort);
End;

// ---------------------------------------------------------------------------
// Helper: Get next available hotkey (skips reserved keys L, P, Q)
// ---------------------------------------------------------------------------
Function GetNextHotkey : String;
Const
  ValidKeys = '123456789ABCDEFGHJKMNORSTUVWXYZ';
Var
  I, J    : Byte;
  Ch      : Char;
  IsTaken : Boolean;
Begin
  GetNextHotkey := 'X';
  For I := 1 To Length(ValidKeys) Do Begin
    Ch := ValidKeys[I];
    IsTaken := False;
    For J := 1 To BBSCount Do Begin
      If Upper(BBSList[J].Hotkey) = Ch Then Begin
        IsTaken := True;
        Break;
      End;
    End;
    If Not IsTaken Then Begin
      GetNextHotkey := Ch;
      Exit;
    End;
  End;
End;

// ---------------------------------------------------------------------------
// Edit or Add a BBS Listing Entry (Supports Telnet & SSH Modes)
// ---------------------------------------------------------------------------
Procedure EditBBSEntry(Idx : Byte; IsNew : Boolean);
Var
  ScopeChoice : Char;
Begin
  ClrScr;
  WriteXYPipe(1, 1, 31, 79, ' |15|17 EDITING BBS DIRECTORY LISTING #' + Int2Str(Idx));

  Repeat
    GotoXY(3, 4);
    WritePipe('|11Hotkey (1-9, A-Z)        : |15');
    BBSList[Idx].Hotkey := Upper(Input(2, 2, 11, BBSList[Idx].Hotkey));
    If (BBSList[Idx].Hotkey = 'L') Or (BBSList[Idx].Hotkey = 'P') Or (BBSList[Idx].Hotkey = 'Q') Then Begin
      GotoXY(3, 5);
      WritePipe('|12Keys L (Lightbar), P (Ping), and Q (Quit) are reserved gateway controls! |PA');
      GotoXY(3, 5);
      WritePipe(RepChar(' ', 72));
    End;
  Until (BBSList[Idx].Hotkey <> 'L') And (BBSList[Idx].Hotkey <> 'P') And (BBSList[Idx].Hotkey <> 'Q');

  GotoXY(3, 6);
  WritePipe('|11BBS System Name          : |15');
  BBSList[Idx].Name := Input(30, 30, 11, BBSList[Idx].Name);

  GotoXY(3, 8);
  WritePipe('|11Host / IP (or user@host) : |15');
  WritePipeLn('|08(For SSH: host, user@host, or user:pass@host)');
  GotoXY(30, 8);
  BBSList[Idx].Host := Input(40, 45, 11, BBSList[Idx].Host);

  GotoXY(3, 10);
  WritePipe('|11Port (23=Telnet, 22=SSH) : |15');
  BBSList[Idx].Port := Input(6, 6, 20, BBSList[Idx].Port);
  If StripB(BBSList[Idx].Port, ' ') = '' Then BBSList[Idx].Port := '23';

  GotoXY(3, 12);
  WritePipeLn('|11Connection Mode          : |15[L]|07ocal Telnet   |15[E]|07xternal Telnet');
  GotoXY(30, 13);
  WritePipe('|15[S]|07SH Local      |15[X]|07 SSH External : ');
  ScopeChoice := OneKey('LESX' + #13, False);
  Case ScopeChoice Of
    'L': BBSList[Idx].Scope := 'LOCAL';
    'E': BBSList[Idx].Scope := 'EXTERNAL';
    'S': BBSList[Idx].Scope := 'SSH-LOC';
    'X': BBSList[Idx].Scope := 'SSH-EXT';
  End;
  WritePipeLn('|14' + BBSList[Idx].Scope);

  GotoXY(3, 15);
  WritePipe('|11Short Description        : |15');
  BBSList[Idx].Description := Input(48, 60, 11, BBSList[Idx].Description);

  Modified := True;
  DrawMainScreen;
  DrawBBSList;
End;

Procedure AddBBSEntry;
Begin
  If BBSCount >= MaxBBS Then Begin
    GotoXY(1, 22);
    WritePipe('|12Maximum number of BBS listings reached! |PA');
    Exit;
  End;

  BBSCount := BBSCount + 1;
  SelectedIdx := BBSCount;
  BBSList[BBSCount].Hotkey := GetNextHotkey;

  BBSList[BBSCount].Name        := 'New BBS Node';
  BBSList[BBSCount].Host        := '127.0.0.1';
  BBSList[BBSCount].Port        := '2323';
  BBSList[BBSCount].Scope       := 'LOCAL';
  BBSList[BBSCount].Description := 'Local BBS Node';

  EditBBSEntry(BBSCount, True);
End;

Procedure DeleteBBSEntry;
Var
  I : Byte;
Begin
  If BBSCount = 0 Then Exit;
  GotoXY(3, 22);
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
// Gateway Options, Inbound SSH & Lightbar Color Editor Submenu
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
    WriteXYPipe(1, 1, 31, 79, ' |15|17 GATEWAY SERVER, INBOUND SSH & LIGHTBAR OPTIONS');
    GotoXY(1, 3);
    WritePipeLn(' |15[1]|07 Gateway Title            : |11' + GwTitle);
    WritePipeLn(' |15[2]|07 SysOp Name               : |11' + SysopName);
    WritePipeLn(' |15[3]|07 Listen Address           : |11' + ListenHost);
    WritePipeLn(' |15[4]|07 Telnet Listen Port       : |11' + ListenPort);
    WritePipeLn(' |15[5]|07 ANSI Art File            : |11' + AnsiFile);
    WritePipeLn(' |15[6]|07 Display Mode (Toggle)    : |14' + DisplayMode + ' |08(BOTH / LIGHTBAR / ANSI_HOTKEY)');
    WritePipeLn(' |15[7]|07 Lightbar Start X / Y     : |11X=' + Int2Str(MenuStartX) + ', Y=' + Int2Str(MenuStartY) + ', Width=' + Int2Str(MenuWidth) + ', Rows=' + Int2Str(MenuRows));
    WritePipeLn(' |15[8]|07 Idle / Connect Timeouts  : |11Idle=' + Int2Str(IdleTimeout) + 's, Connect=' + Int2Str(ConnectTimeout) + 's');
    WritePipeLn(' |15[9]|07 Return After Disconnect  : |14' + BoolToCfg(ReturnAfterDisconnect));
    WritePipeLn(' |15[S]|07 Inbound SSH Server       : |14' + BoolToCfg(SshEnabled) + ' |08(Port: |11' + SshListenPort + '|08, Key: |11' + SshHostKey + '|08)');
    WritePipeLn(' |15[C]|07 Lightbar Colors (FG/BG)  : |11Item(' + Int2Str(ColorItemFG) + '/' + Int2Str(ColorItemBG) + ')  Hilite(' + Int2Str(ColorHiliteFG) + '/' + Int2Str(ColorHiliteBG) + ')  Border(' + Int2Str(ColorBorder) + ')');
    WritePipeLn('');
    WritePipe(' |09Select Option |01[|151-9, S, C|01]|09 or |01[|15Q|01]|09 Return to Listings: |15');

    OptKey := OneKey('123456789SCQ' + #27, False);
    Case OptKey Of
      '1': Begin
             GotoXY(3, 17);
             WritePipe('|11New Gateway Title: ');
             GwTitle := Input(45, 60, 11, GwTitle);
             Modified := True;
           End;
      '2': Begin
             GotoXY(3, 17);
             WritePipe('|11SysOp Name: ');
             SysopName := Input(30, 40, 11, SysopName);
             Modified := True;
           End;
      '3': Begin
             GotoXY(3, 17);
             WritePipe('|11Listen Host IP (0.0.0.0 for all): ');
             ListenHost := Input(25, 40, 11, ListenHost);
             Modified := True;
           End;
      '4': Begin
             GotoXY(3, 17);
             WritePipe('|11Telnet Listen Port (default 23): ');
             ListenPort := Input(6, 6, 20, ListenPort);
             Modified := True;
           End;
      '5': Begin
             GotoXY(3, 17);
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
             GotoXY(3, 17);
             WritePipe('|11Lightbar Start X (1-40)  : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuStartX));
             MenuStartX := Str2Int(TmpStr);
             GotoXY(3, 18);
             WritePipe('|11Lightbar Start Y (1-20)  : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuStartY));
             MenuStartY := Str2Int(TmpStr);
             GotoXY(3, 19);
             WritePipe('|11Lightbar Width (40-77)   : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuWidth));
             MenuWidth := Str2Int(TmpStr);
             GotoXY(3, 20);
             WritePipe('|11Visible Rows (3-15)      : ');
             TmpStr := Input(4, 4, 20, Int2Str(MenuRows));
             MenuRows := Str2Int(TmpStr);
             Modified := True;
           End;
      '8': Begin
             GotoXY(3, 17);
             WritePipe('|11Idle Timeout (seconds)   : ');
             TmpStr := Input(6, 6, 20, Int2Str(IdleTimeout));
             IdleTimeout := Str2Int(TmpStr);
             GotoXY(3, 18);
             WritePipe('|11Connect Timeout (seconds): ');
             TmpStr := Input(6, 6, 20, Int2Str(ConnectTimeout));
             ConnectTimeout := Str2Int(TmpStr);
             Modified := True;
           End;
      '9': Begin
             ReturnAfterDisconnect := Not ReturnAfterDisconnect;
             Modified := True;
           End;
      'S': Begin
             SshEnabled := Not SshEnabled;
             GotoXY(3, 17);
             WritePipe('|11Inbound SSH Port (default 2222): ');
             SshListenPort := Input(6, 6, 20, SshListenPort);
             GotoXY(3, 18);
             WritePipe('|11SSH Host Key File              : ');
             SshHostKey := Input(40, 80, 11, SshHostKey);
             Modified := True;
           End;
      'C': Begin
             GotoXY(3, 17);
             WritePipe('|11Normal Item FG (0-15)    : ');
             ColorItemFG := Str2Int(Input(3, 3, 20, Int2Str(ColorItemFG)));
             GotoXY(3, 18);
             WritePipe('|11Normal Item BG (0-7)     : ');
             ColorItemBG := Str2Int(Input(3, 3, 20, Int2Str(ColorItemBG)));
             GotoXY(3, 19);
             WritePipe('|11Highlight Bar FG (0-15)  : ');
             ColorHiliteFG := Str2Int(Input(3, 3, 20, Int2Str(ColorHiliteFG)));
             GotoXY(3, 20);
             WritePipe('|11Highlight Bar BG (0-7)   : ');
             ColorHiliteBG := Str2Int(Input(3, 3, 20, Int2Str(ColorHiliteBG)));
             GotoXY(3, 21);
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
        #72: If SelectedIdx > 1 Then Begin
               SelectedIdx := SelectedIdx - 1;
               DrawBBSList;
             End;
        #80: If SelectedIdx < BBSCount Then Begin
               SelectedIdx := SelectedIdx + 1;
               DrawBBSList;
             End;
        #71: Begin
               SelectedIdx := 1;
               DrawBBSList;
             End;
        #79: If BBSCount > 0 Then Begin
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
               GotoXY(1, 23);
               WritePipe('|07Press any key to return to Gateway Config... |PA');
               DrawMainScreen;
               DrawBBSList;
             End;
        'P': Begin
               GotoXY(3, 22);
               WritePipe('|11Path to gateway.cfg: ');
               CfgFilePath := Input(50, 120, 11, CfgFilePath);
               LoadConfig;
               DrawMainScreen;
               DrawBBSList;
             End;
        'S': Begin
               SaveConfig;
               GotoXY(3, 22);
               WritePipe('|10Configuration saved to ' + CfgFilePath + '! |PA');
               DrawMainScreen;
               DrawBBSList;
             End;
        'Q', #27: Begin
               If Modified Then Begin
                 GotoXY(3, 22);
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
