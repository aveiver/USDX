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
 * $URL: $
 * $Id: $
 *}

unit UScreenJukeboxPlaylist;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UFiles,
  UMenu,
  UModernUI,
  UMusic,
  UNote,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenJukeboxPlaylist = class(TMenu)
    private
      SelectPlayList:  cardinal;
      SelectPlayList2: cardinal;

      IPlaylist:  array of UTF8String;
      IPlaylist2: array of UTF8String;

      PlayList:  integer;
      PlayList2: integer;

      // ui-v2 (Midnight) start screen
      FRow:        integer;   // 0 what to play, 1 which list, 2 options, 3 start
      FToggle:     integer;   // 0 shuffle, 1 lyrics, 2 repeat
      FPillScroll: single;
      FCardRects:   array[0..2] of TMRect;
      FToggleRects: array[0..2] of TMRect;
      FPillRects:   array of TMRect;
      FPillIdx:     array of integer;
      FBackRect, FStartRect: TMRect;

      procedure SetPlaylists;
      procedure SetMode(Mode: integer);
      procedure SetRow(Row: integer);
      procedure Toggle(Index: integer);
      procedure StartJukebox;
      procedure GoBack;
      function HasChoices: boolean;
    public
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function Draw: boolean; override;
      procedure OnShow; override;

      procedure InitJukebox;
  end;

const
  ID='ID_040';   //for help system

implementation

uses
  UGraphic,
  UHelp,
  UMain,
  UIni,
  ULanguage,
  ULog,
  UParty,
  USong,
  UPlaylist,
  UScreenJukebox,
  USongs,
  UUnicodeUtils;

{ =====================================================================
  ui-v2: Midnight jukebox start screen
  Rows: 0 = what to play (all songs / a category / a playlist),
        1 = which category or playlist, 2 = shuffle / lyrics / repeat,
        3 = start. The old "manual" mode isn't offered.
  ===================================================================== }

const
  JP_PAD = 56;

function TScreenJukeboxPlaylist.HasChoices: boolean;
begin
  Result := (PlayList = 1) or (PlayList = 2);
end;

procedure TScreenJukeboxPlaylist.SetMode(Mode: integer);
begin
  if (Mode < 0) or (Mode > 2) or (Mode = PlayList) then
    Exit;
  PlayList := Mode;
  SetPlaylists;
  FPillScroll := 0;
end;

procedure TScreenJukeboxPlaylist.SetRow(Row: integer);
begin
  if (Row < 0) then
    Row := 0;
  if (Row > 3) then
    Row := 3;
  FRow := Row;
end;

procedure TScreenJukeboxPlaylist.Toggle(Index: integer);
begin
  case Index of
    0: JukeboxStartShuffle := not JukeboxStartShuffle;
    1: JukeboxStartLyrics := not JukeboxStartLyrics;
    2: JukeboxStartRepeat := not JukeboxStartRepeat;
  end;
end;

procedure TScreenJukeboxPlaylist.GoBack;
begin
  AudioPlayback.PlaySound(SoundLib.Back);
  FadeTo(@ScreenMain);
end;

procedure TScreenJukeboxPlaylist.StartJukebox;
var
  Report: string;
  I, Cats: integer;
begin
  // nothing to play in this mode
  if (PlayList = 1) then
  begin
    Cats := 0;
    for I := 0 to High(CatSongs.Song) do
      if CatSongs.Song[I].Main then
        Inc(Cats);
    if (Cats = 0) then
      Exit;
  end;
  if (PlayList = 2) and (Length(PlaylistMan.Playlists) = 0) then
    Exit;

  // remember the start options for next time
  JukeboxSaveSettings;

  try
    InitJukebox;
  except
    on E : Exception do
    begin
      Report := 'Starting jukebox failed. Most likely no folder / empty folder / paylist with not available songs was selected.' + LineEnding +
        'Stacktrace:' + LineEnding;
      if E <> nil then
      begin
        Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
          'Message: ' + E.Message + LineEnding;
      end;
      Report := Report + BackTraceStrFunc(ExceptAddr);
      for I := 0 to ExceptFrameCount - 1 do
      begin
        Report := Report + LineEnding + BackTraceStrFunc(ExceptFrames[I]);
      end;
      Log.LogWarn(Report, 'UScreenJukeboxPlaylist.StartJukebox');
    end;
  end;
end;

function TScreenJukeboxPlaylist.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
begin
  Result := true;
  if not PressedDown then
    Exit;

  case PressedKey of
    SDLK_Q:
      begin
        Result := false;
        Exit;
      end;

    SDLK_ESCAPE,
    SDLK_BACKSPACE:
      GoBack;

    SDLK_TAB:
      ScreenPopupHelp.ShowPopup();

    SDLK_SPACE:
      if (FRow = 2) then
        Toggle(FToggle);

    SDLK_RETURN:
      if (FRow = 2) then
        Toggle(FToggle)
      else
        StartJukebox;

    SDLK_DOWN:
      if (FRow = 0) and not HasChoices then
        SetRow(2)
      else
        SetRow(FRow + 1);

    SDLK_UP:
      if (FRow = 2) and not HasChoices then
        SetRow(0)
      else
        SetRow(FRow - 1);

    SDLK_RIGHT:
      case FRow of
        0: SetMode(PlayList + 1);
        1: if (PlayList2 < High(IPlaylist2)) then Inc(PlayList2);
        2: if (FToggle < 2) then Inc(FToggle);
      end;

    SDLK_LEFT:
      case FRow of
        0: SetMode(PlayList - 1);
        1: if (PlayList2 > 0) then Dec(PlayList2);
        2: if (FToggle > 0) then Dec(FToggle);
      end;
  end;
end;

function TScreenJukeboxPlaylist.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  VX, VY: single;
  I: integer;
begin
  Result := true;
  if not BtnDown then
    Exit;

  case MouseButton of
    SDL_BUTTON_RIGHT:
      GoBack;
    SDL_BUTTON_WHEELDOWN:
      if HasChoices and (PlayList2 < High(IPlaylist2)) then
        Inc(PlayList2);
    SDL_BUTTON_WHEELUP:
      if HasChoices and (PlayList2 > 0) then
        Dec(PlayList2);
    SDL_BUTTON_LEFT:
      begin
        MWindowToVirtual(X, Y, VX, VY);
        if MHit(VX, VY, FBackRect) then
        begin
          GoBack;
          Exit;
        end;
        if MHit(VX, VY, FStartRect) then
        begin
          SetRow(3);
          StartJukebox;
          Exit;
        end;
        for I := 0 to 2 do
          if MHit(VX, VY, FCardRects[I]) then
          begin
            SetMode(I);
            SetRow(0);
            Exit;
          end;
        for I := 0 to 2 do
          if MHit(VX, VY, FToggleRects[I]) then
          begin
            FToggle := I;
            Toggle(I);
            SetRow(2);
            Exit;
          end;
        for I := 0 to High(FPillRects) do
          if MHit(VX, VY, FPillRects[I]) then
          begin
            PlayList2 := FPillIdx[I];
            SetRow(1);
            Exit;
          end;
      end;
  end;
end;

function TScreenJukeboxPlaylist.Draw: boolean;
var
  I, N, Songs: integer;
  X, Y, W, CardW, ViewW, Total, SelX, SelW, Target, MaxScroll: single;
  R, Ring: TMRect;
  Sel, Small: boolean;
  Title, Sub, Lbl: UTF8String;
  Widths: array of single;
begin
  MBegin;
  MFillRect(0, 0, MUI_W, MUI_H, mcBg, 1);

  { header }
  FBackRect := MRect(JP_PAD, 34, 44, 44);
  MFillCircle(JP_PAD + 22, 56, 22, mcSurface, 1);
  MStrokeRound(JP_PAD, 34, 44, 44, 22, 1, mcBorder, 1);
  MIconBack(JP_PAD + 22, 56, 24, mcText, 1);
  MText(JP_PAD + 64, 32, 'Jukebox', 30, true, mcText, 1);
  MText(JP_PAD + 64, 70, 'Pick what plays. Videos and lyrics run on their own, no singing needed.', 15, false, mcMuted, 1);

  { what to play }
  Songs := 0;
  for I := 0 to High(CatSongs.Song) do
    if not CatSongs.Song[I].Main then
      Inc(Songs);

  CardW := (MUI_W - 2 * JP_PAD - 2 * 20) / 3;
  for I := 0 to 2 do
  begin
    R := MRect(JP_PAD + I * (CardW + 20), 118, CardW, 190);
    FCardRects[I] := R;
    Sel := (I = PlayList);
    if Sel then
      MFillRound(R.X, R.Y, R.W, R.H, 22, mcSurface2, 1)
    else
      MFillRound(R.X, R.Y, R.W, R.H, 22, mcSurface, 1);
    MStrokeRound(R.X, R.Y, R.W, R.H, 22, 1, mcBorder, 1);

    // icon tile
    if Sel then
      MFillRound(R.X + 26, R.Y + 26, 48, 48, 14, mcAccent, 1)
    else
      MFillRound(R.X + 26, R.Y + 26, 48, 48, 14, mcBorder, 1);
    case I of
      0:
        begin
          if Sel then
            MIconNote(R.X + 50, R.Y + 50, 24, mcOnAccent, 1)
          else
            MIconNote(R.X + 50, R.Y + 50, 24, mcText, 1);
          Title := 'All songs';
          Sub := IntToStr(Songs) + ' songs';
        end;
      1:
        begin
          if Sel then
          begin
            MFillRound(R.X + 38, R.Y + 38, 10, 10, 2, mcOnAccent, 1);
            MFillRound(R.X + 52, R.Y + 38, 10, 10, 2, mcOnAccent, 1);
            MFillRound(R.X + 38, R.Y + 52, 10, 10, 2, mcOnAccent, 1);
            MFillRound(R.X + 52, R.Y + 52, 10, 10, 2, mcOnAccent, 1);
          end
          else
          begin
            MStrokeRound(R.X + 38, R.Y + 38, 10, 10, 2, 2, mcText, 1);
            MStrokeRound(R.X + 52, R.Y + 38, 10, 10, 2, 2, mcText, 1);
            MStrokeRound(R.X + 38, R.Y + 52, 10, 10, 2, 2, mcText, 1);
            MStrokeRound(R.X + 52, R.Y + 52, 10, 10, 2, 2, mcText, 1);
          end;
          Title := 'One category';
          Sub := 'One group from your song list';
        end;
    else
      begin
        if Sel then
        begin
          MFillRect(R.X + 38, R.Y + 39, 18, 2.5, mcOnAccent, 1);
          MFillRect(R.X + 38, R.Y + 47, 18, 2.5, mcOnAccent, 1);
          MFillRect(R.X + 38, R.Y + 55, 12, 2.5, mcOnAccent, 1);
          MFillRect(R.X + 57, R.Y + 53, 8, 2.5, mcOnAccent, 1);
          MFillRect(R.X + 59.75, R.Y + 50.25, 2.5, 8, mcOnAccent, 1);
        end
        else
        begin
          MFillRect(R.X + 38, R.Y + 39, 18, 2.5, mcText, 1);
          MFillRect(R.X + 38, R.Y + 47, 18, 2.5, mcText, 1);
          MFillRect(R.X + 38, R.Y + 55, 12, 2.5, mcText, 1);
          MFillRect(R.X + 57, R.Y + 53, 8, 2.5, mcText, 1);
          MFillRect(R.X + 59.75, R.Y + 50.25, 2.5, 8, mcText, 1);
        end;
        Title := 'A playlist';
        if (Length(PlaylistMan.Playlists) = 1) then
          Sub := '1 saved playlist'
        else
          Sub := IntToStr(Length(PlaylistMan.Playlists)) + ' saved playlists';
      end;
    end;
    MText(R.X + 26, R.Y + 112, Title, 24, true, mcText, 1, mtaLeft, R.W - 52);
    MText(R.X + 26, R.Y + 148, Sub, 15, false, mcMuted, 1, mtaLeft, R.W - 52);
  end;

  { which category or playlist }
  SetLength(FPillRects, 0);
  SetLength(FPillIdx, 0);
  Y := 372;
  if HasChoices then
  begin
    if (PlayList = 1) then
      Lbl := 'Categories'
    else
      Lbl := 'Playlists';
    MText(JP_PAD, Y - 34, Lbl, 15, false, mcMuted, 1);

    N := Length(IPlaylist2);
    SetLength(Widths, N);
    Total := 0;
    SelX := 0;
    SelW := 0;
    for I := 0 to N - 1 do
    begin
      Widths[I] := MTextW(IPlaylist2[I], 15, I = PlayList2) + 40;
      if (I = PlayList2) then
      begin
        SelX := Total;
        SelW := Widths[I];
      end;
      Total := Total + Widths[I] + 10;
    end;

    // keep the chosen pill in view
    ViewW := MUI_W - 2 * JP_PAD;
    MaxScroll := Total - 10 - ViewW;
    if (MaxScroll < 0) then
      MaxScroll := 0;
    Target := SelX + SelW / 2 - ViewW / 2;
    if (Target < 0) then
      Target := 0;
    if (Target > MaxScroll) then
      Target := MaxScroll;
    FPillScroll := MApproach(FPillScroll, Target, 14);

    MClipBegin(MRect(JP_PAD - 8, Y - 8, ViewW + 16, 64));
    X := JP_PAD - FPillScroll;
    for I := 0 to N - 1 do
    begin
      R := MRect(X, Y, Widths[I], 48);
      if (X + Widths[I] > JP_PAD - 8) and (X < JP_PAD + ViewW + 8) then
      begin
        SetLength(FPillRects, Length(FPillRects) + 1);
        SetLength(FPillIdx, Length(FPillIdx) + 1);
        FPillRects[High(FPillRects)] := R;
        FPillIdx[High(FPillIdx)] := I;
        if (I = PlayList2) then
        begin
          MFillRound(R.X, R.Y, R.W, R.H, 24, mcText, 1);
          MText(R.X + 20, R.Y + 15, IPlaylist2[I], 15, true, mcBg, 1);
        end
        else
        begin
          MFillRound(R.X, R.Y, R.W, R.H, 24, mcSurface, 1);
          MStrokeRound(R.X, R.Y, R.W, R.H, 24, 1, mcBorder, 1);
          MText(R.X + 20, R.Y + 15, IPlaylist2[I], 15, false, mcMuted, 1);
        end;
      end;
      X := X + Widths[I] + 10;
    end;
    MClipEnd;
  end;

  { shuffle / lyrics / repeat }
  Y := 586;
  X := JP_PAD;
  for I := 0 to 2 do
  begin
    case I of
      0: begin Lbl := 'Shuffle'; Sel := JukeboxStartShuffle; end;
      1: begin Lbl := 'Lyrics'; Sel := JukeboxStartLyrics; end;
    else
      begin Lbl := 'Repeat list'; Sel := JukeboxStartRepeat; end;
    end;
    W := MTextW(Lbl, 16, false) + 22 + 12 + 48 + 12;
    R := MRect(X, Y, W, 52);
    FToggleRects[I] := R;
    MFillRound(R.X, R.Y, R.W, R.H, 26, mcSurface, 1);
    MStrokeRound(R.X, R.Y, R.W, R.H, 26, 1, mcBorder, 1);
    MText(R.X + 22, R.Y + 16, Lbl, 16, false, mcText, 1);
    // switch
    if Sel then
    begin
      MFillRound(R.X + R.W - 60, R.Y + 12, 48, 28, 14, mcAccent, 1);
      MFillCircle(R.X + R.W - 60 + 34, R.Y + 26, 11, mcOnAccent, 1);
    end
    else
    begin
      MFillRound(R.X + R.W - 60, R.Y + 12, 48, 28, 14, mcBorder, 1);
      MFillCircle(R.X + R.W - 60 + 14, R.Y + 26, 11, mcMuted, 1);
    end;
    X := X + W + 14;
  end;

  // start button
  Lbl := 'Start jukebox';
  W := MTextW(Lbl, 20, true) + 90;
  FStartRect := MRect(MUI_W - JP_PAD - W, Y - 4, W, 60);
  R := FStartRect;
  Small := (PlayList = 2) and (Length(PlaylistMan.Playlists) = 0);
  if Small then
  begin
    MFillRound(R.X, R.Y, R.W, R.H, 30, mcSurface2, 1);
    MIconPlay(R.X + 36, R.Y + 30, 18, mcMuted, 1);
    MText(R.X + 56, R.Y + 19, Lbl, 20, true, mcMuted, 1);
  end
  else
  begin
    MFillRound(R.X, R.Y, R.W, R.H, 30, mcAccent, 1);
    MIconPlay(R.X + 36, R.Y + 30, 18, mcOnAccent, 1);
    MText(R.X + 56, R.Y + 19, Lbl, 20, true, mcOnAccent, 1);
  end;

  { selection ring }
  case FRow of
    0: Ring := FCardRects[PlayList];
    1:
      begin
        Ring := MRect(0, 0, 0, 0);
        for I := 0 to High(FPillRects) do
          if (FPillIdx[I] = PlayList2) then
            Ring := FPillRects[I];
      end;
    2: Ring := FToggleRects[FToggle];
  else
    Ring := FStartRect;
  end;
  if (Ring.W > 0) then
  begin
    if (FRow = 0) then
      MStrokeRound(Ring.X - 6, Ring.Y - 6, Ring.W + 12, Ring.H + 12, 28, 3, mcText, 1)
    else
      MStrokeRound(Ring.X - 6, Ring.Y - 6, Ring.W + 12, Ring.H + 12, (Ring.H + 12) / 2, 3, mcText, 1);
  end;

  { footer }
  X := JP_PAD;
  X := X + MKeyHint(X, 682, 'Up/Down', 'move') + 22;
  X := X + MKeyHint(X, 682, 'Left/Right', 'choose') + 22;
  if (FRow = 2) then
    X := X + MKeyHint(X, 682, 'Enter', 'switch') + 22
  else
    X := X + MKeyHint(X, 682, 'Enter', 'start') + 22;
  MKeyHint(X, 682, 'Esc', 'back');

  MEnd;
  Result := true;
end;

constructor TScreenJukeboxPlaylist.Create;
begin
  inherited Create;

  //Clear all Selects
  PlayList := 0;
  PlayList2 := 0;

  // playlist modes
  SetLength(IPlaylist2, 1);
  IPlaylist2[0] := '---';

  SetLength(IPlaylist, 4);

  IPlaylist[0] := Language.Translate('PARTY_PLAYLIST_ALL');
  IPlaylist[1] := Language.Translate('PARTY_PLAYLIST_CATEGORY');
  IPlaylist[2] := Language.Translate('PARTY_PLAYLIST_PLAYLIST');
  IPlaylist[3] := Language.Translate('PARTY_PLAYLIST_MANUAL');

  //Load Screen From Theme
  LoadFromTheme(Theme.JukeboxPlaylist);

  Theme.JukeboxPlaylist.SelectPlayList.oneItemOnly := true;
  Theme.JukeboxPlaylist.SelectPlayList.showArrows := true;
  SelectPlayList  := AddSelectSlide(Theme.JukeboxPlaylist.SelectPlayList, PlayList, IPlaylist);

  Theme.JukeboxPlaylist.SelectPlayList2.oneItemOnly := true;
  Theme.JukeboxPlaylist.SelectPlayList2.showArrows := true;
  SelectPlayList2 := AddSelectSlide(Theme.JukeboxPlaylist.SelectPlayList2, PlayList2, IPlaylist2);

  Interaction := 0;
end;

procedure TScreenJukeboxPlaylist.SetPlaylists;
var
  I: integer;
begin
  case Playlist of
    0:
      begin
        SetLength(IPlaylist2, 1);
        IPlaylist2[0] := '---';
      end;
    1:
      begin
        SetLength(IPlaylist2, 0);
        for I := 0 to high(CatSongs.Song) do
        begin
          if (CatSongs.Song[I].Main) then
          begin
            SetLength(IPlaylist2, Length(IPlaylist2) + 1);
            IPlaylist2[high(IPlaylist2)] := CatSongs.Song[I].Artist;
          end;
        end;

        if (Length(IPlaylist2) = 0) then
        begin
          SetLength(IPlaylist2, 1);
          IPlaylist2[0] := 'No Categories found';
        end;
      end;
    2:
      begin
        if (Length(PlaylistMan.Playlists) > 0) then
        begin
          SetLength(IPlaylist2, Length(PlaylistMan.Playlists));
          PlaylistMan.GetNames(IPlaylist2);
        end
        else
        begin
          SetLength(IPlaylist2, 1);
          IPlaylist2[0] := 'No Playlists found';
        end;
      end;
    3:
      begin
        SetLength(IPlaylist2, 1);
        IPlaylist2[0] := '---';
      end;
  end;

  Playlist2 := 0;
  UpdateSelectSlideOptions(SelectPlayList2, IPlaylist2, Playlist2);
end;

procedure TScreenJukeboxPlaylist.OnShow;
begin
  inherited;

  // ui-v2
  JukeboxLoadSettings;
  if (PlayList > 2) then
    PlayList := 0;
  SetPlaylists;
  FRow := 0;
  FToggle := 0;
  FPillScroll := 0;

  if not Help.SetHelpID(ID) then
    Log.LogError('No Entry for Help-ID ' + ID + ' (ScreenJukeboxPlaylist)');

end;

procedure TScreenJukeboxPlaylist.InitJukebox;
var
  I, J: integer;
begin
  ScreenSong.Mode := smJukebox;
  AudioPlayback.PlaySound(SoundLib.Start);

  SetLength(ScreenJukebox.JukeboxSongsList, 0);
  SetLength(ScreenJukebox.JukeboxVisibleSongs, 0);

  ScreenJukebox.ActualInteraction := 0;
  ScreenJukebox.CurrentSongList := 0;
  ScreenJukebox.ListMin := 0;
  ScreenJukebox.Interaction := 0;

  if PlayList = 0 then
  begin
    for I := 0 to High(CatSongs.Song) do
    begin
      if not (CatSongs.Song[I].Main) then
        ScreenJukebox.AddSongToJukeboxList(I);
    end;

    ScreenJukebox.CurrentSongID := ScreenJukebox.JukeboxVisibleSongs[0];

    FadeTo(@ScreenJukebox);
  end;

  if Playlist = 1 then
  begin
    J := -1;
    for I := 0 to high(CatSongs.Song) do
    begin
      if CatSongs.Song[I].Main then
        Inc(J);

      if J = Playlist2 then
      begin
        ScreenJukebox.AddSongToJukeboxList(I);
      end;
    end;

    ScreenJukebox.CurrentSongID := ScreenJukebox.JukeboxVisibleSongs[0];

    FadeTo(@ScreenJukebox);
  end;

  if Playlist = 2 then
  begin
    if(High(PlaylistMan.PlayLists[Playlist2].Items)>=0) then
    begin
    for I := 0 to High(PlaylistMan.PlayLists[Playlist2].Items) do
    begin
      ScreenJukebox.AddSongToJukeboxList(PlaylistMan.PlayLists[Playlist2].Items[I].SongID);
    end;

    ScreenJukebox.CurrentSongID := ScreenJukebox.JukeboxVisibleSongs[0];

    FadeTo(@ScreenJukebox);
    end
    else
    begin
      Log.LogWarn('Can not play selected playlist in JukeBox because playlist is empty or no song found.', 'ScreenJukeboxPlaylist.InitJukeBox');
    end;
  end;

  if PlayList = 3 then
  begin
    FadeTo(@ScreenSong);
  end;

end;

end.

