{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenOptions.pas $
 * $Id: UScreenOptions.pas 2649 2010-10-10 10:34:20Z tobigun $
 *}

unit UScreenOptions;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UFiles,
  UIni,
  UMenu,
  UModernUI,
  UMusic,
  USongs,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenOptions = class(TMenu)
    private
      ButtonGameIID,
      ButtonGraphicsIID,
      ButtonSoundIID,
      ButtonInputIID,
      ButtonLyricsIID,
      ButtonThemesIID,
      ButtonRecordIID,
      ButtonAdvancedIID,
      ButtonNetworkIID,
      ButtonWebcamIID,
      ButtonJukeboxIID,
      ButtonExitIID: cardinal;

      MapIIDtoDescID: array of integer;

      procedure UpdateTextDescriptionFor(IID: integer); virtual;
      procedure OpenRecordOptions;

    private
      // ui-v2 (Midnight) grid
      FTileRects: array of TMRect;
      FBackRect: TMRect;
      FRingX, FRingY, FRingW, FRingH: single;
      FRingReady: boolean;
      function TileCount: integer;
      procedure MoveGrid(DX, DY: integer);

    public
      TextDescription:    integer;
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      procedure OnShow; override;
      procedure SetInteraction(Num: integer); override;
      function Draw: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
  end;

const
  ID='ID_070';   //for help system

implementation

uses
  UDatabase,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UScreenOptionsRecord,
  UWebcam,
  UUnicodeUtils;

procedure TScreenOptions.OpenRecordOptions;
begin
  RefreshAudioInputDevices(aimFull);
  FreeAndNil(ScreenOptionsRecord);
  ScreenOptionsRecord := TScreenOptionsRecord.Create;
  FadeTo(@ScreenOptionsRecord, SoundLib.Start);
end;

function TScreenOptions.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
begin
  Result := true;
  if (PressedDown) then
  begin // Key Down
    // check normal keys
    case PressedKey of
      SDLK_G:
        begin
          FadeTo(@ScreenOptionsGame, SoundLib.Start);
          Exit;
        end;

      SDLK_H:
        begin
          FadeTo(@ScreenOptionsGraphics, SoundLib.Start);
          Exit;
        end;

      SDLK_S:
        begin
          FadeTo(@ScreenOptionsSound, SoundLib.Start);
          Exit;
        end;

      SDLK_I:
        begin
          FadeTo(@ScreenOptionsInput, SoundLib.Start);
          Exit;
        end;

      SDLK_L:
        begin
          FadeTo(@ScreenOptionsLyrics, SoundLib.Start);
          Exit;
        end;

      SDLK_T:
        begin
          FadeTo(@ScreenOptionsThemes, SoundLib.Start);
          Exit;
        end;

      SDLK_R:
        begin
          OpenRecordOptions;
          Exit;
        end;

      SDLK_A:
        begin
          FadeTo(@ScreenOptionsAdvanced, SoundLib.Start);
          Exit;
        end;

      SDLK_N:
        begin
          if (High(DataBase.NetworkUser) = -1) then
            ScreenPopupError.ShowPopup(Language.Translate('SING_OPTIONS_NETWORK_NO_DLL'))
          else
          begin
            AudioPlayback.PlaySound(SoundLib.Back);
            FadeTo(@ScreenOptionsNetwork);
          end;
          Exit;
        end;

      SDLK_W:
        begin
          FadeTo(@ScreenOptionsWebcam, SoundLib.Start);
          Exit;
        end;

      SDLK_J:
        begin
          FadeTo(@ScreenOptionsJukebox, SoundLib.Start);
          Exit;
        end;

      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE :
        begin
          Ini.Save;
          AudioPlayback.PlaySound(SoundLib.Back);
          FadeTo(@ScreenMain);
        end;

      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;

      SDLK_RETURN:
        begin
          if Interaction = ButtonGameIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsGame);
          end;

          if Interaction = ButtonGraphicsIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsGraphics);
          end;

          if Interaction = ButtonSoundIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsSound);
          end;

          if Interaction = ButtonInputIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsInput);
          end;

          if Interaction = ButtonLyricsIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsLyrics);
          end;

          if Interaction = ButtonThemesIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsThemes);
          end;

          if Interaction = ButtonRecordIID then
          begin
            OpenRecordOptions;
          end;

          if Interaction = ButtonAdvancedIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenOptionsAdvanced);
          end;

          if Interaction = ButtonNetworkIID then
          begin
            if ((High(DataBase.NetworkUser) = -1)) then
              ScreenPopupError.ShowPopup(Language.Translate('SING_OPTIONS_NETWORK_NO_DLL'))
            else
            begin
              AudioPlayback.PlaySound(SoundLib.Back);
              FadeTo(@ScreenOptionsNetwork);
            end;
          end;

          if Interaction = ButtonWebcamIID then
          begin
            AudioPlayback.PlaySound(SoundLib.Back);
            FadeTo(@ScreenOptionsWebcam);
          end;

          if Interaction = ButtonJukeboxIID then
          begin
            if (Songs.SongList.Count >= 1) then
            begin
              AudioPlayback.PlaySound(SoundLib.Start);
              FadeTo(@ScreenOptionsJukebox);
            end
            else //show error message, No Songs Loaded
              ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_SONGS'));
          end;

          if Interaction = ButtonExitIID then
          begin
            Ini.Save;
            AudioPlayback.PlaySound(SoundLib.Back);
            FadeTo(@ScreenMain);
          end;
        end;
      SDLK_DOWN:    MoveGrid(0, 1);
      SDLK_UP:      MoveGrid(0, -1);
      SDLK_RIGHT:   MoveGrid(1, 0);
      SDLK_LEFT:    MoveGrid(-1, 0);
    end;
  end;
end;

constructor TScreenOptions.Create;

  // TODO: Generalize method and implement it into base code (to be used by every screen/menu)
  function AddButtonChecked(Btn: TThemeButton; DescIndex: byte; out IIDvar: cardinal; AddX: real = 14; AddY: real = 20): cardinal;
  var OldPos: integer;
  begin
    OldPos := Length(Button);
    Result := AddButton(Btn);
    if Length(Button) <> OldPos then // check if button was succesfully added // TODO: RattleSN4K3: Improve AddButton interface returning properly index to be used by interaction check
    begin
      IIDvar := High(Interactions);

      // update mapping, IID to Desc index
      SetLength(MapIIDtoDescID, IIDvar+1);
      MapIIDtoDescID[IIDvar] := DescIndex;

      if (Length(Button[Result].Text) = 0) then // update text if not already set
        AddButtonText(AddX, AddY, Theme.Options.Description[DescIndex]);
    end;

  end;
begin
  inherited Create;

  TextDescription := AddText(Theme.Options.TextDescription);
  Text[TextDescription].Visible := false;

  LoadFromTheme(Theme.Options);

  // Theme.Options.Text[1] (OptionsText2, static "Change settings" subheader)
  // becomes Text[2] here: TextDescription was added first (index 0), then
  // LoadFromTheme adds OptionsText1..5 starting at index 1.
  Text[2].Visible := false;

  // Order is irrelevant to the represenatation, however InteractNext/Prev is not working with a different order // TODO: RattleSN4K3: allow InteractNext etc. work with themes having a different button layout
  AddButtonChecked(Theme.Options.ButtonGame, OPTIONS_DESC_INDEX_GAME,  ButtonGameIID);
  AddButtonChecked(Theme.Options.ButtonGraphics, OPTIONS_DESC_INDEX_GRAPHICS,  ButtonGraphicsIID);
  AddButtonChecked(Theme.Options.ButtonSound, OPTIONS_DESC_INDEX_SOUND,  ButtonSoundIID);
  AddButtonChecked(Theme.Options.ButtonInput, OPTIONS_DESC_INDEX_INPUT,  ButtonInputIID);

  AddButtonChecked(Theme.Options.ButtonLyrics, OPTIONS_DESC_INDEX_LYRICS,  ButtonLyricsIID);
  AddButtonChecked(Theme.Options.ButtonThemes, OPTIONS_DESC_INDEX_THEMES,  ButtonThemesIID);
  AddButtonChecked(Theme.Options.ButtonRecord, OPTIONS_DESC_INDEX_RECORD,  ButtonRecordIID);
  AddButtonChecked(Theme.Options.ButtonAdvanced, OPTIONS_DESC_INDEX_ADVANCED,  ButtonAdvancedIID);
  AddButtonChecked(Theme.Options.ButtonNetwork, OPTIONS_DESC_INDEX_NETWORK,  ButtonNetworkIID);

  AddButtonChecked(Theme.Options.ButtonWebcam, OPTIONS_DESC_INDEX_WEBCAM,  ButtonWebcamIID);
  AddButtonChecked(Theme.Options.ButtonJukebox, OPTIONS_DESC_INDEX_JUKEBOX,  ButtonJukeboxIID);

  AddButtonChecked(Theme.Options.ButtonExit, OPTIONS_DESC_INDEX_BACK,  ButtonExitIID);

  Interaction := 0;
end;

procedure TScreenOptions.OnShow;
begin
  inherited;
  FRingReady := false;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenOptions');

  // continue possibly stopped bg-music (stopped in record options)
  SoundLib.StartBgMusic;
end;

procedure TScreenOptions.SetInteraction(Num: integer);
begin
  inherited SetInteraction(Num);
  UpdateTextDescriptionFor(Interaction);
end;

procedure TScreenOptions.UpdateTextDescriptionFor(IID: integer);
begin
  // Sanity check
  if (IID < 0 ) or (IID >= Length(MapIIDtoDescID)) then
    Exit;

  Text[TextDescription].Text := Theme.Options.Description[MapIIDtoDescID[IID]];
end;

{ ui-v2: Midnight options hub - a grid of tiles, Back in the header }

const
  OH_PAD  = 56;
  OH_COLS = 4;
  OH_SHORTCUTS: array[0..10] of string = ('G', 'H', 'S', 'I', 'L', 'T', 'R', 'A', 'N', 'W', 'J');

// tiles are every interaction except the Back button (the last one)
function TScreenOptions.TileCount: integer;
begin
  Result := Length(Interactions) - 1;
  if (Result < 0) then
    Result := 0;
end;

procedure TScreenOptions.MoveGrid(DX, DY: integer);
var
  N, Cur, Nxt: integer;
begin
  N := TileCount;
  Cur := Interaction;

  if (Cur >= N) then
  begin
    // on Back: down/right goes to the first tile
    if (DY > 0) or (DX > 0) then
      Interaction := 0;
    Exit;
  end;

  if (DX <> 0) then
  begin
    Nxt := Cur + DX;
    if (Nxt >= 0) and (Nxt < N) then
      Interaction := Nxt;
  end
  else if (DY < 0) then
  begin
    if (Cur < OH_COLS) then
      Interaction := N  // up from the first row: Back
    else
      Interaction := Cur - OH_COLS;
  end
  else if (DY > 0) then
  begin
    Nxt := Cur + OH_COLS;
    if (Nxt < N) then
      Interaction := Nxt
    else if ((Cur div OH_COLS) < ((N - 1) div OH_COLS)) then
      Interaction := N - 1; // short last row
  end;
end;

function TScreenOptions.Draw: boolean;
var
  I, N: integer;
  TileW, TileH, X, Y: single;
  R, Ring: TMRect;
  Lbl, Desc: UTF8String;
begin
  MBegin;
  MFillRect(0, 0, MUI_W, MUI_H, mcBg, 1);

  // header
  FBackRect := MRect(OH_PAD, 34, 44, 44);
  if (Interaction >= TileCount) then
    MFillCircle(OH_PAD + 22, 56, 22, mcText, 1)
  else
    MFillCircle(OH_PAD + 22, 56, 22, mcSurface, 1);
  MStrokeRound(OH_PAD, 34, 44, 44, 22, 1, mcBorder, 1);
  if (Interaction >= TileCount) then
    MIconBack(OH_PAD + 22, 56, 24, mcBg, 1)
  else
    MIconBack(OH_PAD + 22, 56, 24, mcText, 1);
  MText(OH_PAD + 64, 40, Language.Translate('SING_OPTIONS'), 30, true, mcText, 1);

  // description of the selected tile
  Desc := '';
  if (TextDescription >= 0) and (TextDescription <= High(Text)) then
    Desc := Text[TextDescription].Text;
  MText(OH_PAD, 108, Desc, 18, false, mcMuted, 1, mtaLeft, MUI_W - 2 * OH_PAD);

  // tiles
  N := TileCount;
  SetLength(FTileRects, N);
  TileW := (MUI_W - 2 * OH_PAD - (OH_COLS - 1) * 20) / OH_COLS;
  TileH := 132;
  for I := 0 to N - 1 do
  begin
    X := OH_PAD + (I mod OH_COLS) * (TileW + 20);
    Y := 150 + (I div OH_COLS) * (TileH + 20);
    R := MRect(X, Y, TileW, TileH);
    FTileRects[I] := R;

    if (I = Interaction) then
      MFillRound(R.X, R.Y, R.W, R.H, 20, mcSurface2, 1)
    else
      MFillRound(R.X, R.Y, R.W, R.H, 20, mcSurface, 1);
    MStrokeRound(R.X, R.Y, R.W, R.H, 20, 1, mcBorder, 1);

    Lbl := '';
    if (Interactions[I].Typ = iButton) and (Length(Button[Interactions[I].Num].Text) > 0) then
      Lbl := Button[Interactions[I].Num].Text[0].Text;
    MText(R.X + 24, R.Y + R.H - 52, Lbl, 26, true, mcText, 1, mtaLeft, R.W - 48);

    // keyboard shortcut chip
    if (I <= High(OH_SHORTCUTS)) then
    begin
      MFillRound(R.X + R.W - 46, R.Y + 16, 30, 28, 8, mcBg, 1);
      MText(R.X + R.W - 31, R.Y + 21, OH_SHORTCUTS[I], 15, true, mcMuted, 1, mtaCenter);
    end;
  end;

  // selection ring
  if (Interaction < N) and (Interaction >= 0) then
  begin
    Ring := FTileRects[Interaction];
    if not FRingReady then
    begin
      FRingX := Ring.X; FRingY := Ring.Y; FRingW := Ring.W; FRingH := Ring.H;
      FRingReady := true;
    end
    else
    begin
      FRingX := MApproach(FRingX, Ring.X, 16);
      FRingY := MApproach(FRingY, Ring.Y, 16);
      FRingW := MApproach(FRingW, Ring.W, 16);
      FRingH := MApproach(FRingH, Ring.H, 16);
    end;
    MStrokeRound(FRingX - 6, FRingY - 6, FRingW + 12, FRingH + 12, 26, 3, mcText, 1);
  end;

  // footer
  X := OH_PAD;
  X := X + MKeyHint(X, 682, 'Arrows', 'move') + 22;
  X := X + MKeyHint(X, 682, 'Enter', 'open') + 22;
  MKeyHint(X, 682, 'Esc', 'back');

  MEnd;
  Result := true;
end;

function TScreenOptions.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  VX, VY: single;
  I: integer;
begin
  Result := true;
  if not BtnDown then
    Exit;

  if (MouseButton = SDL_BUTTON_RIGHT) then
    Result := ParseInput(SDLK_ESCAPE, 0, true)
  else if (MouseButton = SDL_BUTTON_LEFT) then
  begin
    MWindowToVirtual(X, Y, VX, VY);
    if MHit(VX, VY, FBackRect) then
    begin
      Result := ParseInput(SDLK_ESCAPE, 0, true);
      Exit;
    end;
    for I := 0 to High(FTileRects) do
      if MHit(VX, VY, FTileRects[I]) then
      begin
        Interaction := I;
        Result := ParseInput(SDLK_RETURN, 0, true);
        Exit;
      end;
  end;
end;

end.
