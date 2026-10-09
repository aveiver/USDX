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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenMain.pas $
 * $Id: UScreenMain.pas 3128 2015-08-28 01:45:23Z basisbit $
 *}

unit UScreenMain;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UMenu,
  UModernUI,
  sdl2,
  SysUtils;

type
  {
    Midnight main menu (ui-v2).
    Items: 0 Sing (big card), 1 Jukebox (card), 2 Options, 3 Exit (header pills).
    Drawn with UModernUI instead of the theme's 800x600 buttons.
  }
  TScreenMain = class(TMenu)
  private
    FSel: integer;
    // animated selection ring
    FRingX, FRingY, FRingW, FRingH: single;
    FRingReady: boolean;
    function ItemRect(Index: integer): TMRect;
    procedure Activate(Index: integer; var KeepGoing: boolean);
    procedure MoveSel(DX, DY: integer);
  public
    constructor Create; override;
    function ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
      PressedDown: boolean): boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    procedure OnShow; override;
    function Draw: boolean; override;
  end;

const
  ID = 'ID_001';   //for help system

  MAIN_SING    = 0;
  MAIN_JUKEBOX = 1;
  MAIN_OPTIONS = 2;
  MAIN_EXIT    = 3;

var
  WantSoftwareRenderingMsg: boolean;

implementation

uses
  UDisplay,
  UGraphic,
  UHelp,
  UIni,
  ULanguage,
  ULog,
  UMusic,
  UNote,
  UParty,
  URenderer,
  UScreenSong,
  USong,
  USongs,
  UThemes,
  UConfig;

const
  PAD = 56;

constructor TScreenMain.Create;
begin
  inherited Create;
  FSel := MAIN_SING;
  FRingReady := false;
  WantSoftwareRenderingMsg := Renderer.SoftwareRendering;
end;

procedure TScreenMain.OnShow;
begin
  inherited;

  SoundLib.StartBgMusic;

  ScreenSong.Mode := smNormal;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenMains');

  // Clean up TPartyGame here; at the moment there is no better place for this
  Party.Clear;

  FRingReady := false;
end;

{ layout }

function TScreenMain.ItemRect(Index: integer): TMRect;
var
  CardsY, CardsH, CardsW, SingW, PillW: single;
begin
  CardsY := 330;
  CardsH := 270;
  CardsW := MUI_W - 2 * PAD - 20;
  SingW := CardsW * 0.6;

  case Index of
    MAIN_SING:
      Result := MRect(PAD, CardsY, SingW, CardsH);
    MAIN_JUKEBOX:
      Result := MRect(PAD + SingW + 20, CardsY, CardsW - SingW, CardsH);
    MAIN_OPTIONS:
      begin
        PillW := MTextW(Language.Translate('SING_OPTIONS'), 17, false) + 40;
        Result := MRect(MUI_W - PAD - (MTextW(Language.Translate('SING_EXIT'), 17, false) + 40) - 10 - PillW, 36, PillW, 46);
      end;
  else // MAIN_EXIT
    begin
      PillW := MTextW(Language.Translate('SING_EXIT'), 17, false) + 40;
      Result := MRect(MUI_W - PAD - PillW, 36, PillW, 46);
    end;
  end;
end;

{ input }

procedure TScreenMain.MoveSel(DX, DY: integer);
begin
  // cards row: Sing, Jukebox   /   header row: Options, Exit
  if (DY < 0) and (FSel in [MAIN_SING, MAIN_JUKEBOX]) then
    FSel := MAIN_OPTIONS
  else if (DY > 0) and (FSel in [MAIN_OPTIONS, MAIN_EXIT]) then
    FSel := MAIN_SING
  else if (DX > 0) then
  begin
    case FSel of
      MAIN_SING:    FSel := MAIN_JUKEBOX;
      MAIN_OPTIONS: FSel := MAIN_EXIT;
    end;
  end
  else if (DX < 0) then
  begin
    case FSel of
      MAIN_JUKEBOX: FSel := MAIN_SING;
      MAIN_EXIT:    FSel := MAIN_OPTIONS;
    end;
  end;
end;

procedure TScreenMain.Activate(Index: integer; var KeepGoing: boolean);
begin
  // reset
  Party.bPartyGame := false;

  case Index of
    MAIN_SING:
      begin
        if (Songs.SongList.Count >= 1) then
        begin
          if (Ini.Players >= 0) and (Ini.Players <= 3) then
            PlayersPlay := Ini.Players + 1;
          if (Ini.Players = 4) then
            PlayersPlay := 6;

          if Ini.OnSongClick = sSelectPlayer then
            FadeTo(@ScreenSong)
          else
          begin
            ScreenName.Goto_SingScreen := false;
            FadeTo(@ScreenName, SoundLib.Start);
          end;
        end
        else
          ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_SONGS'));
      end;

    MAIN_JUKEBOX:
      begin
        if (Songs.SongList.Count >= 1) then
          FadeTo(@ScreenJukeboxPlaylist, SoundLib.Start)
        else
          ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_SONGS'));
      end;

    MAIN_OPTIONS:
      FadeTo(@ScreenOptions, SoundLib.Start);

    MAIN_EXIT:
      KeepGoing := false;
  end;
end;

function TScreenMain.ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
  PressedDown: boolean): boolean;
begin
  Result := true;

  if not PressedDown then
    Exit;

  case PressedKey of
    SDLK_S:
      begin
        FSel := MAIN_SING;
        Activate(MAIN_SING, Result);
      end;

    SDLK_J:
      begin
        FSel := MAIN_JUKEBOX;
        Activate(MAIN_JUKEBOX, Result);
      end;

    SDLK_O:
      begin
        FSel := MAIN_OPTIONS;
        Activate(MAIN_OPTIONS, Result);
      end;

    SDLK_R:
      begin
        UGraphic.UnLoadScreens();
        Theme.LoadTheme(Ini.Theme, Ini.Color);
        UGraphic.LoadScreens(USDXVersionStr);
      end;

    SDLK_Q,
    SDLK_ESCAPE,
    SDLK_BACKSPACE:
      Result := false;

    SDLK_TAB:
      ScreenPopupHelp.ShowPopup();

    SDLK_RETURN:
      Activate(FSel, Result);

    SDLK_DOWN:  MoveSel(0, 1);
    SDLK_UP:    MoveSel(0, -1);
    SDLK_RIGHT: MoveSel(1, 0);
    SDLK_LEFT:  MoveSel(-1, 0);
  end;
end;

function TScreenMain.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  VX, VY: single;
  I: integer;
begin
  Result := true;

  if (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then
  begin
    Result := ParseInput(SDLK_ESCAPE, 0, true);
    Exit;
  end;

  MWindowToVirtual(X, Y, VX, VY);
  for I := MAIN_SING to MAIN_EXIT do
    if MHit(VX, VY, ItemRect(I)) then
    begin
      FSel := I;
      if BtnDown and (MouseButton = SDL_BUTTON_LEFT) then
        Activate(I, Result);
      Exit;
    end;
end;

{ drawing }

procedure DrawCard(const R: TMRect; const Title, Caption: UTF8String;
  Primary, Selected: boolean; Icon: integer);
var
  Fg, Sub: TMColor;
  TitleSize: single;
begin
  if Primary then
  begin
    MFillRound(R.X, R.Y, R.W, R.H, 24, mcAccent, 1);
    Fg := mcOnAccent;
    Sub := mcOnAccent;
    TitleSize := 44;
  end
  else
  begin
    if Selected then
      MFillRound(R.X, R.Y, R.W, R.H, 24, mcSurface2, 1)
    else
      MFillRound(R.X, R.Y, R.W, R.H, 24, mcSurface, 1);
    MStrokeRound(R.X, R.Y, R.W, R.H, 24, 1, mcBorder, 1);
    Fg := mcText;
    Sub := mcMuted;
    TitleSize := 32;
  end;

  if Icon = 0 then
    MIconPlay(R.X + 52, R.Y + 56, 36, Fg, 1)
  else
    MIconNote(R.X + 50, R.Y + 54, 38, Fg, 1);

  MText(R.X + 32, R.Y + R.H - 34 - 22 - TitleSize, Title, TitleSize, true, Fg, 1, mtaLeft, R.W - 64);
  MText(R.X + 32, R.Y + R.H - 34 - 18, Caption, 18, false, Sub, 1, mtaLeft, R.W - 64);
end;

procedure DrawPill(const R: TMRect; const Caption: UTF8String; Selected: boolean);
begin
  if Selected then
  begin
    MFillRound(R.X, R.Y, R.W, R.H, R.H / 2, mcText, 1);
    MText(R.X + R.W / 2, R.Y + 13, Caption, 17, true, mcBg, 1, mtaCenter);
  end
  else
  begin
    MStrokeRound(R.X, R.Y, R.W, R.H, R.H / 2, 1, mcBorder, 1);
    MText(R.X + R.W / 2, R.Y + 13, Caption, 17, false, mcMuted, 1, mtaCenter);
  end;
end;

function TScreenMain.Draw: boolean;
var
  R: TMRect;
  X, ChipW: single;
  Status: UTF8String;
begin
  MBegin;

  // background
  MFillRect(0, 0, MUI_W, MUI_H, mcBg, 1);

  // header: wordmark + pills
  MIconMic(PAD + 14, 59, 30, mcAccent, 1);
  MText(PAD + 40, 46, 'UltraStar', 24, true, mcText, 1);
  DrawPill(ItemRect(MAIN_OPTIONS), Language.Translate('SING_OPTIONS'), FSel = MAIN_OPTIONS);
  DrawPill(ItemRect(MAIN_EXIT), Language.Translate('SING_EXIT'), FSel = MAIN_EXIT);

  // headline
  MText(PAD, 128, IntToStr(Songs.SongList.Count) + ' songs ready', 19, false, mcMuted, 1);
  MText(PAD, 160, 'Pick a song.', 72, true, mcText, 1);
  MText(PAD, 236, 'Grab a mic.', 72, true, mcText, 1);

  // cards
  DrawCard(ItemRect(MAIN_SING), Language.Translate('SING_SING'),
    'Browse your songs and start singing', true, FSel = MAIN_SING, 0);
  DrawCard(ItemRect(MAIN_JUKEBOX), Language.Translate('SING_JUKEBOX'),
    'Play songs with lyrics on screen', false, FSel = MAIN_JUKEBOX, 1);

  // selection ring glides between items
  R := ItemRect(FSel);
  if not FRingReady then
  begin
    FRingX := R.X; FRingY := R.Y; FRingW := R.W; FRingH := R.H;
    FRingReady := true;
  end
  else
  begin
    FRingX := MApproach(FRingX, R.X, 14);
    FRingY := MApproach(FRingY, R.Y, 14);
    FRingW := MApproach(FRingW, R.W, 14);
    FRingH := MApproach(FRingH, R.H, 14);
  end;
  if FSel in [MAIN_SING, MAIN_JUKEBOX] then
    MStrokeRound(FRingX - 7, FRingY - 7, FRingW + 14, FRingH + 14, 30, 3, mcText, 1);

  // footer: scoring status + key hints
  if Boolean(Ini.KaraokeMode) then
    Status := 'Scoring off'
  else
    Status := 'Scoring on';
  ChipW := MTextW(Status, 15, false) + 44;
  MFillRound(PAD, 650, ChipW, 34, 17, mcSurface, 1);
  if Boolean(Ini.KaraokeMode) then
    MFillCircle(PAD + 18, 667, 4, mcMuted, 1)
  else
    MFillCircle(PAD + 18, 667, 4, mcGood, 1);
  MText(PAD + 30, 658, Status, 15, false, mcMuted, 1);

  X := MUI_W - PAD - 330;
  X := X + MKeyHint(X, 660, 'Arrows', 'move') + 24;
  X := X + MKeyHint(X, 660, 'Enter', 'select') + 24;
  MKeyHint(X, 660, 'Esc', 'quit');

  MEnd;

  if not ScreenPopupError.Visible then
  begin
    if WantSoftwareRenderingMsg then
    begin
      WantSoftwareRenderingMsg := false;
      ScreenPopupError.ShowPopup(Language.Translate('ERROR_SOFTWARE_RENDERING'));
    end;
  end;

  Result := true;
end;

end.
