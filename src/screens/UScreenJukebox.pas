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
 * $Id:  $
 *}

unit UScreenJukebox;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UDataBase,
  UFiles,
  UGraphicClasses,
  UHookableEvent,
  UIni,
  ULyrics,
  UMenu,
  UModernUI,
  UMusic,
  UPath,
  UPlaylist,
  URenderer,
  USingScores,
  USongs,
  UThemes,
  UTime,
  UVideo,
  UWebcam,
  sdl2,
  SysUtils,
  UText;

type
  TSongJukebox = class
  public
    Id: integer;

    // sorting methods
    Genre:      UTF8String;
    Edition:    UTF8String;
    Language:   UTF8String;
    Year:       Integer;

    Title:      UTF8String;
    Artist:     UTF8String;

  end;

  THandler = record
    changed:  boolean;
    change_time:  real;
  end;

  TLyricsSyncSource = class(TSyncSource)
    function GetClock(): real; override;
  end;

  TMusicSyncSource = class(TSyncSource)
    function GetClock(): real; override;
  end;

  TTimebarMode = (
    tbmCurrent,   // current song position
    tbmRemaining, // remaining time
    tbmTotal      // total time
  );

type
  TScreenJukebox = class(TMenu)
  private
    // move song
    MoveX, MoveY: real;
    MoveInicial, MoveFinal: integer;
    MoveSong: boolean;

    // items
    JukeboxStaticTimeProgress:       integer;
    JukeboxStaticTimeBackground:     integer;
    JukeboxStaticSongBackground:     integer;
    JukeboxStaticSongListBackground: integer;
    SongDescription:  array[0..9] of integer;
    SongDescriptionClone: integer;

    JukeboxStaticActualSongStatic: array of integer;
    JukeboxStaticActualSongCover:           integer;
    JukeboxTextActualSongArtist:            integer;
    JukeboxTextActualSongTitle:             integer;

    JukeboxSongListUp:   integer;
    JukeboxSongListDown: integer;

    // Jukebox SongMenu items
    JukeboxSongMenuPlayPause:            integer;
    JukeboxSongMenuPlaylist:             integer;
    JukeboxSongMenuOptions:              integer;
    JukeboxSongMenuNext:                 integer;
    JukeboxSongMenuPrevious:             integer;
    JukeboxStaticSongMenuTimeProgress:   integer;
    JukeboxStaticSongMenuTimeBackground: integer;
    JukeboxTextSongMenuTimeText:         integer;
    JukeboxStaticSongMenuBackground:     integer;

    SelectColR: real;
    SelectColG: real;
    SelectColB: real;

    JukeboxTextTimeText: integer;
    //JukeboxTextSongText: integer;

    tmpLyricsUpperY: real;
    tmpLyricsLowerY: real;
    //tmp_mouse: integer;

    JukeboxFindSong:       integer;
    JukeboxRepeatSongList: integer;
    JukeboxSongListOrder:  integer;
    JukeboxRandomSongList: integer;
    JukeboxListText:       integer;
    JukeboxCountText:      integer;
    JukeboxLyric:          integer;
    JukeboxOptions:        integer;
    JukeboxSongListClose:  integer;
    JukeboxSongListFixPin: integer;
    JukeboxPlayPause:      integer;

    Filter:         UTF8String;

    FindSongList:   boolean;
    RepeatSongList: boolean;
    RandomMode:     boolean;
    OrderMode:      boolean;
    OrderType:      integer;

    fShowVisualization: boolean;
    fShowWebcam:        boolean;
    fShowBackground:    boolean;

    fCurrentVideo: IVideo;
    fVideoClip:    IVideo;
    fLyricsSync:   TLyricsSyncSource;
    fMusicSync:    TMusicSyncSource;
    fTimebarMode:  TTimebarMode;

    // ui-v2 (Midnight) jukebox
    FDisplayVisible: boolean;           // display settings card open
    FDisplayRow:     integer;           // 0 video, 1 lyrics, 2 shade, 3-5 colours, 6 buttons
    FDisplayBtn:     integer;           // 0 reset, 1 save
    FDisplaySaved:   cardinal;          // tick of the last save (for "Saved")
    FDisplayCard:    TMRect;
    FDispRects:      array of TMRect;   // clickable parts of the card
    FDispCodes:      array of integer;  // Row * 100 + value (see DisplayClick)
    FBarRects:       array[0..8] of TMRect;
    FPanelRows:      array of TMRect;
    FPanelRowIdx:    array of integer;
    FChipRects:      array[0..2] of TMRect;
    FSearchRect:     TMRect;
    FPanelTop:       integer;

    function BarShown: boolean;
    procedure ShowBar;
    procedure SyncCurrentIndex;
    procedure SetSort(Order: integer);
    procedure ToggleSearch;
    procedure OpenDisplay;
    procedure ChangeDisplayValue(Row, Delta: integer);
    procedure DisplayClick(Code: integer; VX: single);
    function ParseDisplayInput(PressedKey: cardinal): boolean;
    function ParseMouseModern(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
    procedure AddDispRect(const R: TMRect; Code: integer);
    procedure DrawModernLyrics;
    procedure DrawModernBar;
    procedure DrawModernPanel;
    procedure DrawModernDisplay;
    procedure DrawModern;

  protected
    eSongLoaded:       THookableEvent; //< event is called after lyrics of a song are loaded on OnShow
    Paused:            boolean; //pause Mod
    NumEmptySentences: integer;

  public
    ShowLyrics:  boolean;
    LyricsStart: boolean;

    CurrentSongList:     integer;
    LastTick:            cardinal;
    LastSongMenuTick:    cardinal;
    LastSongOptionsTick: cardinal;
    DoubleClickTime:     cardinal;
    CloseClickTime:      cardinal;
    SongListVisible:     boolean;
    SongListVisibleFix:  boolean;
    SongMenuVisible:     boolean;
    LastTickChangeSong:  cardinal;
    MouseDownList:       cardinal;
    MoveDown:            boolean;
    MouseUpList:         cardinal;
    MoveUp:              boolean;

    JukeboxSongsList:     array of integer;
    JukeboxVisibleSongs:  array of integer;

    ActualInteraction:   integer;
    ListMin:             integer;
    CurrentSongID:       integer;

    //VideoAspect
    VideoAspectText:     integer;
    VideoAspectStatic:   integer;
    AspectHandler:       THandler;
    AspectCorrection:    TAspectCorrection;

    Tex_Background: TTexture;
    FadeOut: boolean;
    Lyrics:  TLyricEngine;
    LyricsAlpha : real;
    StaticCover: integer;
    LyricHelper: TRGB;

    constructor Create; override;
    destructor Destroy; override;
    procedure OnShow; override;
    procedure OnShowFinish; override;
    procedure OnHide; override;

    function ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
      PressedDown: boolean): boolean; override;
    function ParseMouse(MouseButton: Integer; BtnDown: Boolean; X, Y: integer): boolean; override;

    function Draw: boolean; override;
    procedure DrawBlackBars();

    procedure PlayMusic(ID: integer; ShowList: boolean);
    procedure Play;
    procedure Finish;
    procedure Pause; // toggle pause

    procedure OnSentenceChange(SentenceIndex: cardinal);  // for golden notes

    procedure DeleteSong(Id: integer);
    procedure FilterSongList(Filter: UTF8String);
    procedure GoToSongList(UpperLetter: UCS4Char);
    procedure SongListSort(Order: integer);
    procedure Sort(Order: integer);
    procedure Reset;

    procedure AddSongToJukeboxList(ID: integer);
    function FinishedMusic: boolean;

    procedure RefreshCover;
    procedure DrawPlaylist;
    procedure DrawMoveLine;
    procedure DrawSongInfo;
    procedure DrawSongMenu;

    procedure ChangeTime(Time: real);
    procedure ChangeSongPosition(Start, Final: integer);
    procedure ChangeOrderList();
    procedure RandomList();

    procedure PageDown(N: integer);
    procedure PageUp(N: integer);

    procedure ChangeLyricPosition(N: integer);
    procedure ChangeVideoWidth(N: integer);
    procedure ChangeVideoHeight(N: integer);

    procedure LoadJukeboxSongOptions();
  end;

const
  ID='ID_041';   //for help system

// ui-v2 jukebox settings, kept in config.ini [JukeboxUI]
var
  JukeboxFit:      integer = 0;    // video: 0 fill (crop), 1 fit (letterbox), 2 halfway
  JukeboxLyricPos: integer = 1;    // 1 bottom, 2 middle, 3 top
  JukeboxShade:    integer = 6;    // shade behind the lyrics, 0..10
  JukeboxColSung:  integer = 0;    // index into the sung palette
  JukeboxColTodo:  integer = 0;    // still to sing
  JukeboxColNext:  integer = 0;    // next line
  JukeboxStartShuffle: boolean = false;
  JukeboxStartLyrics:  boolean = true;
  JukeboxStartRepeat:  boolean = false;

procedure JukeboxLoadSettings;
procedure JukeboxSaveSettings;

implementation

uses
  UBeatTimer,
  UDisplay,
  UDraw,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UMain,
  UMenuButton,
  UMenuInteract,
  UNote,
  UParty,
  URecord,
  USkins,
  UScreenJukeboxOptions,
  UModernSing,
  USong,
  UUnicodeUtils,
  Classes,
  IniFiles,
  Math;

const
  MAX_TIME_PLAYLIST = 4000; // msec

  MAX_TIME_SONGDESC = 2000; // msec
  MAX_TIME_FADESONGDESC = 2000; // msec

  MAX_TIME_MOUSE_CHANGELIST = 300; // msec

  MAX_TIME_MOUSE_CLOSE = 500; // msec

  MAX_TIME_SONGMENU = 3000; // msec

  MAX_TIME_SONGOPTIONS = 3000; // msec

procedure TScreenJukebox.DrawMoveLine();
begin
  Renderer.DrawQuad(MoveX, MoveY, 0, Button[SongDescription[0]].Texture.W, 2, SelectColR, SelectColG, SelectColB, 1);
end;

procedure TScreenJukebox.DrawBlackBars();
var
  X, X1, Y, Y1, Z, H, W: double;
  QuadList: TQuadList;
begin
  fCurrentVideo.GetScreenPosition(X, Y, Z);
  SetLength(QuadList, 4);

  // Upper
  X1 := 0;
  Y1 := 0;
  H := Y + 1;
  W := 800;

  QuadList[0].X := X1;
  QuadList[0].Y := Y1;
  QuadList[0].Z := 0;
  QuadList[0].W := W;
  QuadList[0].H := H;
  QuadList[0].ColR := 0;
  QuadList[0].ColG := 0;
  QuadList[0].ColB := 0;
  QuadList[0].Alpha := 1;
  QuadList[0].Gradient := gdNone;

  // Bottom
  X1 := 0;
  Y1 := 600;
  H := Y + 1;
  W := 800;

  QuadList[1].X := X1;
  QuadList[1].Y := Y1;
  QuadList[1].Z := 0;
  QuadList[1].W := W;
  QuadList[1].H := H;
  QuadList[1].ColR := 0;
  QuadList[1].ColG := 0;
  QuadList[1].ColB := 0;
  QuadList[1].Alpha := 1;
  QuadList[1].Gradient := gdNone;

  // Left
  X1 := 0;
  Y1 := 0;
  H := 600;
  W := X + 1;

  QuadList[2].X := X1;
  QuadList[2].Y := Y1;
  QuadList[2].Z := 0;
  QuadList[2].W := W;
  QuadList[2].H := H;
  QuadList[2].ColR := 0;
  QuadList[2].ColG := 0;
  QuadList[2].ColB := 0;
  QuadList[2].Alpha := 1;
  QuadList[2].Gradient := gdNone;

  // Right
  X1 := 800;
  Y1 := 0;
  H := 600;
  W := X + 1;

  QuadList[3].X := X1;
  QuadList[3].Y := Y1;
  QuadList[3].Z := 0;
  QuadList[3].W := W;
  QuadList[3].H := H;
  QuadList[3].ColR := 0;
  QuadList[3].ColG := 0;
  QuadList[3].ColB := 0;
  QuadList[3].Alpha := 1;
  QuadList[3].Gradient := gdNone;

  Renderer.DrawQuads(QuadList);
end;

procedure TScreenJukebox.SongListSort(Order: integer);
begin

  case Order of
    1 : begin
          Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_ARTIST');
          Sort(2);
          Sort(1);
        end;
    2 : begin
          Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_TITLE');
          Sort(1);
          Sort(2);
        end;
    3 : begin
          Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_EDITION');
          Sort(2);
          Sort(1);
          Sort(3);
        end;
    4 : begin
          Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_GENRE');
          Sort(2);
          Sort(1);
          Sort(4);
        end;
    5 : begin
          Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_LANGUAGE');
          Sort(2);
          Sort(1);
          Sort(5);
        end;
  end;

end;

procedure TScreenJukebox.Sort(Order: integer);
var
  I, J, X, Comp: integer;
  NotEnd: boolean;
begin

  for I:= 0 to High(JukeboxVisibleSongs) do
  begin
    J := I;
    X := JukeboxVisibleSongs[I];
    NotEnd := true;
    while (J > 0) and (NotEnd) do
    begin

      case Order of
        1 : Comp := UTF8CompareText(CatSongs.Song[X].Artist, CatSongs.Song[JukeboxVisibleSongs[J - 1]].Artist);
        2 : Comp := UTF8CompareText(CatSongs.Song[X].Title, CatSongs.Song[JukeboxVisibleSongs[J - 1]].Title);
        3 : Comp := UTF8CompareText(CatSongs.Song[X].Edition, CatSongs.Song[JukeboxVisibleSongs[J - 1]].Edition);
        4 : Comp := UTF8CompareText(CatSongs.Song[X].Genre, CatSongs.Song[JukeboxVisibleSongs[J - 1]].Genre);
        5 : Comp := UTF8CompareText(CatSongs.Song[X].Language, CatSongs.Song[JukeboxVisibleSongs[J - 1]].Language);
      end;

      if (Comp < 0) then
      begin
        JukeboxVisibleSongs[J] := JukeboxVisibleSongs[J - 1];
        J := J - 1;
      end
      else
        NotEnd := false;
    end;

    JukeboxVisibleSongs[J] := X;
  end;
end;

// TODO: this function does nothing?
procedure TScreenJukebox.GoToSongList(UpperLetter: UCS4Char);
begin
 {

  isCurrentPage := false;
  existNextSong := false;
  CurrentInteractionSong := ActualInteraction;

  for I := ActualInteraction + 1 to High(JukeboxVisibleSongs) do
  begin
    if (OrderType = 2) then
      SongDesc := CatSongs.Song[JukeboxSongsList[I]].TitleNoAccent
    else
      SongDesc := CatSongs.Song[JukeboxSongsList[I]].ArtistNoAccent;

    if (UTF8StartsText(UCS4ToUTF8String(UpperLetter), SongDesc)) then
    begin
      ActualInteraction := I;
      CurrentSongList := I;
      existNextSong := true;
      break;
    end

  end;

  // page songsid
        SetLength(JukeboxSongsListCurrentPage, 0);



  JukeboxSongsList[I]
        SetLength(JukeboxSongsListCurrentPage, Length(JukeboxSongsListCurrentPage) + 1);

        JukeboxSongsListCurrentPage[High(JukeboxSongsListCurrentPage)] := JukeboxVisibleSongs[I + ListMin];

  if (existNextSong) then
  begin
    while not (isCurrentPage) do
    begin

      for S := 0 to High(JukeboxSongsListCurrentPage) do
      begin
        if (JukeboxSongsListCurrentPage[S] = JukeboxSongsList[CurrentSongList]) then
        begin
          isCurrentPage := true;
          break;
        end;
      end;

      if not (isCurrentPage) then
      begin
        PageDown(10);
        ListMin := ListMin + 1;
      end;
    end;
  end;
  }

end;

procedure TScreenJukebox.FilterSongList(Filter: UTF8String);
var
  I: integer;
  SongD: UTF8String;
begin

  if (Filter <> '') then
  begin
    Filter := LowerCase(TransliterateToASCII(UTF8Decode(Filter)));

    SetLength(JukeboxVisibleSongs, 0);
    for I := 0 to High(JukeboxSongsList) do
    begin
      SongD := CatSongs.Song[JukeboxSongsList[I]].ArtistASCII + ' - ' + CatSongs.Song[JukeboxSongsList[I]].TitleASCII;

      if (UTF8ContainsStr(SongD, Filter)) then
      begin
        SetLength(JukeboxVisibleSongs, Length(JukeboxVisibleSongs) + 1);
        JukeboxVisibleSongs[High(JukeboxVisibleSongs)] := JukeboxSongsList[I];
      end;
    end;
  end
  else
  begin
    SetLength(JukeboxVisibleSongs, 0);

    for I := 0 to High(JukeboxSongsList) do
    begin
      SetLength(JukeboxVisibleSongs, Length(JukeboxVisibleSongs) + 1);
      JukeboxVisibleSongs[High(JukeboxVisibleSongs)] := JukeboxSongsList[I];
    end;
  end;

  ActualInteraction := 0;
  Interaction := 0;
  ListMin := 0;
  FPanelTop := 0;

  Button[SongDescription[0]].SetSelect(false);
  SyncCurrentIndex;
end;


procedure TScreenJukebox.DeleteSong(Id: integer);
var
  ALength: Cardinal;
  TailElements: Cardinal;
  IndexVisibleSongs, IndexSongList, I: integer;
begin
  IndexVisibleSongs := Id;

  for I := 0 to High(JukeboxSongsList) do
  begin
    if (JukeboxVisibleSongs[IndexVisibleSongs] = JukeboxSongsList[I]) then
    begin
      IndexSongList := I;
      break;
    end;
  end;

  // visible songs
  ALength := Length(JukeboxVisibleSongs);
  Assert(ALength > 0);
  Assert(IndexVisibleSongs < ALength);
  Finalize(JukeboxVisibleSongs[IndexVisibleSongs]);
  TailElements := ALength - IndexVisibleSongs;
  if TailElements > 0 then
    Move(JukeboxVisibleSongs[IndexVisibleSongs + 1], JukeboxVisibleSongs[IndexVisibleSongs], SizeOf(integer) * TailElements);
  Initialize(JukeboxVisibleSongs[ALength - 1]);
  SetLength(JukeboxVisibleSongs, ALength - 1);

  // all playlist
  ALength := Length(JukeboxSongsList);
  Assert(ALength > 0);
  Assert(IndexSongList < ALength);
  Finalize(JukeboxSongsList[IndexSongList]);
  TailElements := ALength - IndexSongList;
  if TailElements > 0 then
    Move(JukeboxSongsList[IndexSongList + 1], JukeboxSongsList[IndexSongList], SizeOf(integer) * TailElements);
  Initialize(JukeboxSongsList[ALength - 1]);
  SetLength(JukeboxSongsList, ALength - 1);

end;


procedure TScreenJukebox.ChangeLyricPosition(N: integer);
begin
  Lyrics.UpperLineY := Lyrics.UpperLineY + N;
  Lyrics.LowerLineY := Lyrics.LowerLineY + N;
end;

procedure TScreenJukebox.ChangeVideoWidth(N: integer);
var
  X, Y, Z: double;
begin
  fCurrentVideo.GetScreenPosition(X, Y, Z);
  fCurrentVideo.SetScreenPosition(X - (N/2), Y, Z);
  fCurrentVideo.SetWidth(fCurrentVideo.GetWidth + N);
end;

procedure TScreenJukebox.ChangeVideoHeight(N: integer);
var
  X, Y, Z: double;
begin
  fCurrentVideo.GetScreenPosition(X, Y, Z);
  fCurrentVideo.SetScreenPosition(X, Y - (N/2), Z);
  fCurrentVideo.SetHeight(fCurrentVideo.GetHeight + N);
end;

procedure TScreenJukebox.Reset;
begin
  CurrentSongList := 0;

  Interaction       := 0;
  ActualInteraction := 0;
  ListMin           := 0;
  //RepeatSongList    := false;
  RandomMode        := false;
  OrderMode         := true;
  FindSongList      := false;
  Filter            := '';
  ShowLyrics        := true;

  Button[JukeboxSongListOrder].SetSelect(true);

  case (Ini.Sorting) of
    5: begin
         OrderType := 1;
         Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_ARTIST');
       end;
    6: begin
         OrderType := 2;
         Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_TITLE');
       end;
    0: begin
         OrderType := 3;
         Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_EDITION');
       end;
    1: begin
         OrderType := 4;
         Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_GENRE');
       end;
    2: begin
         OrderType := 5;
         Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_LANGUAGE');
       end;
    else
    begin
      OrderType := 1;
      OrderMode := false;
      Button[JukeboxSongListOrder].SetSelect(false);
      try
      Button[JukeboxSongListOrder].Text[0].Text := Language.Translate('OPTION_VALUE_ARTIST');
      finally
      end;

    end;
  end;

  Button[JukeboxFindSong].Text[0].Text := '';

  Button[JukeboxLyric].SetSelect(true);
  Button[JukeboxRandomSongList].SetSelect(false);
  Button[JukeboxRepeatSongList].SetSelect(false);
  Button[JukeboxFindSong].SetSelect(false);
  StopTextInput;
  Button[JukeboxPlayPause].SetSelect(false);
  Button[JukeboxFindSong].Text[0].Selected := false;
end;

procedure OnDeleteSong(Value: boolean; Data: Pointer);
begin
  Display.CheckOK := Value;

  if (Value) then
  begin
    Display.CheckOK := false;

    ScreenJukebox.DeleteSong(ScreenJukebox.ActualInteraction);
  end;
end;

procedure OnEscapeJukebox(Value: boolean; Data: Pointer);
begin
  Display.CheckOK := Value;
  if (Value) then
  begin
    Display.CheckOK := false;

    ScreenJukebox.RepeatSongList := false;

    ScreenJukebox.CurrentSongList := High(ScreenJukebox.JukeboxVisibleSongs);

    ScreenJukebox.Finish;
    ScreenJukebox.FadeOut := true;

    AudioPlayback.PlaySound(SoundLib.Back);

  end;
end;

function TScreenJukebox.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  I, Max: integer;
  Time: real;
begin
  // ui-v2: the Midnight jukebox has its own hit areas
  Result := ParseMouseModern(MouseButton, BtnDown, X, Y);
  Exit;

  //Jukebox Screen Extensions (Options)
  if (ScreenJukeboxOptions.Visible) then
  begin
    Result := ScreenJukeboxOptions.ParseMouse(MouseButton, BtnDown, X, Y);
    Exit;
  end;

  LastTick := SDL_GetTicks();

  Max := 9;
  if (High(JukeboxVisibleSongs) < 9) then
    Max := High(JukeboxVisibleSongs);

  // transfer mousecords to the 800x600 raster we use to draw
  X := Round((X / (ScreenW / Screens)) * RenderW);
  if (X > RenderW) then
    X := X - RenderW;
  Y := Round((Y / ScreenH) * RenderH);

  if (SongListVisible) then
  begin
    // SetTextInput(Button[JukeboxFindSong].Selected);

    if (BtnDown) then //and (MouseButton = SDL_BUTTON_LEFT) then
    begin

      // move song
      if (Button[SongDescriptionClone].Visible) then
      begin
        Button[SongDescriptionClone].X := X;
        Button[SongDescriptionClone].Y := Y;
        Button[SongDescriptionClone].Text[0].X := X + Button[SongDescription[0]].Text[0].X - Button[SongDescription[0]].X;
        Button[SongDescriptionClone].Text[0].Y := Y + Button[SongDescription[0]].Text[0].Y - Button[SongDescription[0]].Y;

        //line position
        MoveSong := false;

        for I := 0 to Max do
        begin
          if InRegionX(X, Button[SongDescription[I]].GetMouseOverArea) then
            MoveSong := true;

          if InRegion(X, Y + Button[SongDescription[I]].Texture.H/2, Button[SongDescription[I]].GetMouseOverArea) then
          begin
            MoveX := Button[SongDescription[I]].Texture.X;
            MoveY := Button[SongDescription[I]].Texture.Y;
            MoveFinal := I + ListMin;
          end;
        end;

        if (MoveSong) and (Y >= Button[SongDescription[Max]].Texture.Y + Button[SongDescription[Max]].Texture.H/2) then
        begin
          MoveX := Button[SongDescription[Max]].Texture.X;
          MoveY := Button[SongDescription[Max]].Texture.Y + Button[SongDescription[Max]].Texture.H;
          MoveFinal := Max + ListMin + 1;
        end;

        if (MoveSong) and (Y >= Button[SongDescription[Max]].Texture.Y + Button[SongDescription[Max]].Texture.H) then
        begin
          MoveX := Button[SongDescription[Max]].Texture.X;
          MoveY := Button[SongDescription[Max]].Texture.Y + Button[SongDescription[Max]].Texture.H;
          MoveFinal := Max + ListMin + 1;

          if (MouseDownList = 0) then
            MouseDownList := SDL_GetTicks()
          else
          begin
            MoveDown := true;
          end;
        end
        else
        begin
          MouseDownList := 0;
          MoveDown := false;
        end;

        if (MoveSong) and (Y <= Button[SongDescription[0]].Texture.Y - Button[SongDescription[0]].Texture.H) then
        begin
          if (MouseUpList = 0) then
            MouseUpList := SDL_GetTicks()
          else
          begin
            MoveUp := true;
          end;
        end
        else
        begin
          MouseUpList := 0;
          MoveUp := false;
        end;
      end
      else
      begin
        //song scrolling with mousewheel
        if (MouseButton = SDL_BUTTON_WHEELDOWN) then
          Result := ParseInput(SDLK_PAGEDOWN, 0, true)

        else if (MouseButton = SDL_BUTTON_WHEELUP) then
          Result := ParseInput(SDLK_PAGEUP, 0, true)

        else
        begin
          // up/down songlist
          if InRegion(X, Y, Button[JukeboxSongListUp].GetMouseOverArea) then
          begin
            PageUp(10);
          end;

          if InRegion(X, Y, Button[JukeboxSongListDown].GetMouseOverArea) then
          begin
            PageDown(10);
          end;

          // change time
          if InRegion(X, Y, Text[JukeboxTextTimeText].GetMouseOverArea) then
          begin
            if (fTimebarMode = High(TTimebarMode)) then
              fTimebarMode := Low(TTimebarMode)
            else
              Inc(fTimebarMode);

            Ini.JukeboxTimebarMode := Ord(fTimebarMode);
            Ini.SaveJukeboxTimebarMode();
          end;

          // play or move song
          for I := 0 to Max do
          begin
            if InRegion(X, Y, Button[SongDescription[I]].GetMouseOverArea) then
            begin

              // start move song
              if not InRegion(X, Y, Button[SongDescription[Interaction]].GetMouseOverArea) then
              begin
                Button[SongDescriptionClone].X := X;
                Button[SongDescriptionClone].Y := Y;
                Button[SongDescriptionClone].Text[0].X := X + Button[SongDescription[I]].Text[0].X - Button[SongDescription[I]].X;
                Button[SongDescriptionClone].Text[0].Y := Y + Button[SongDescription[I]].Text[0].Y - Button[SongDescription[I]].Y;
                Button[SongDescriptionClone].Text[0].Text := CatSongs.Song[JukeboxVisibleSongs[Interaction + ListMin]].Artist + ' - ' + CatSongs.Song[JukeboxVisibleSongs[Interaction + ListMin]].Title;

                MoveX := Button[SongDescription[I]].Texture.X;
                MoveY := Button[SongDescription[I]].Texture.Y;
                MoveInicial := ListMin + Interaction;

                Button[SongDescriptionClone].Visible := true;
                Button[SongDescription[Interaction]].SetSelect(false);
              end
              else
              begin

                if (MouseButton = SDL_BUTTON_LEFT) then
                begin
                  if (SDL_GetTicks() - DoubleClickTime <= 500) then
                    Result := ParseInput(SDLK_RETURN, 0, true);

                  DoubleClickTime := SDL_GetTicks();
                end;

              end;
            end;
          end;

          // close songlist
          if InRegion(X, Y, Button[JukeboxSongListClose].GetMouseOverArea)then
          begin
            Result := ParseInput(SDLK_ESCAPE, 0, true);
            CloseClickTime := SDL_GetTicks();
            Button[JukeboxSongListClose].SetSelect(false);
          end;

          // fix songlist
          if InRegion(X, Y, Button[JukeboxSongListFixPin].GetMouseOverArea)then
          begin
            SongListVisibleFix := not SongListVisibleFix;

            if (SongListVisibleFix) then
              Ini.JukeboxSongMenu := 0
            else
              Ini.JukeboxSongMenu := 1;

            Ini.SaveJukeboxSongMenu;

            Button[JukeboxSongListFixPin].SetSelect(SongListVisibleFix);
          end;

          if InRegion(X, Y, Statics[JukeboxStaticTimeProgress].GetMouseOverArea) then
          begin
            Time := ((X - Statics[JukeboxStaticTimeProgress].Texture.X) * LyricsState.TotalTime)/(Statics[JukeboxStaticTimeProgress].Texture.W);

            ChangeTime(Time);
          end;

          if InRegion(X, Y, Button[JukeboxRepeatSongList].GetMouseOverArea) then
          begin
            RepeatSongList := not RepeatSongList;
            Button[JukeboxRepeatSongList].SetSelect(RepeatSongList);
          end;

          if InRegion(X, Y, Button[JukeboxSongListOrder].GetMouseOverArea) then
          begin
            ChangeOrderList();
          end;

          if InRegion(X, Y, Button[JukeboxRandomSongList].GetMouseOverArea) then
          begin
            RandomList();
          end;

          if InRegion(X, Y, Button[JukeboxLyric].GetMouseOverArea) then
          begin
            ShowLyrics := not ShowLyrics;
            Button[JukeboxLyric].SetSelect(ShowLyrics);
          end;

          if InRegion(X, Y, Button[JukeboxPlayPause].GetMouseOverArea) then
          begin
            Pause;
            Button[JukeboxPlayPause].SetSelect(Paused);
          end;

          if InRegion(X, Y, Button[JukeboxFindSong].GetMouseOverArea) then
          begin
            FindSongList := not FindSongList;

            if (Filter = '') then
            begin
              if (FindSongList) then
                Button[JukeboxFindSong].Text[0].Text := ''
            end;

            Button[JukeboxFindSong].SetSelect(FindSongList);
            SetTextInput(FindSongList);

            if not (FindSongList) and (Length(JukeboxSongsList) <> Length(JukeboxVisibleSongs)) then
            begin
              FilterSongList('');
            end
            else
            begin
              if (Filter <> '') then
                FilterSongList(Filter);
            end;

            if (FindSongList) then
              Button[JukeboxFindSong].Text[0].Selected := true
            else
              Button[JukeboxFindSong].Text[0].Selected := false;

          end;

          if InRegion(X, Y, Button[JukeboxOptions].GetMouseOverArea) then
          begin
            SongMenuVisible := false;
            SongListVisible := false;
            StopTextInput;

            Button[JukeboxOptions].SetSelect(false);
            ScreenJukeboxOptions.Visible := true;

            LastSongOptionsTick := SDL_GetTicks();
          end;

        end;
      end;
    end
    else
    begin

      // change music position
      if (MoveSong) and (ListMin = 0) and (Y <= Button[SongDescription[0]].Texture.Y - Button[SongDescription[0]].Texture.H) then
      begin
        Interaction := 0;
        ActualInteraction := 0;
        Button[SongDescription[0]].SetSelect(true);

        MoveFinal := 0;
      end;

      if (Button[SongDescriptionClone].Visible) and (MoveSong) then
      begin
        if (MoveInicial > MoveFinal) then
          MoveInicial := MoveInicial + 1;

        ChangeSongPosition(MoveInicial, MoveFinal);

        DoubleClickTime := 0;
      end;

      Button[SongDescriptionClone].Visible := false;

      for I := 0 to Max do
      begin
        if InRegion(X, Y, Button[SongDescription[I]].GetMouseOverArea) then
        begin
          Interaction := I;
          ActualInteraction := ListMin + I;
          Button[SongDescription[I]].SetSelect(true);
        end
        else
        begin
          Button[SongDescription[I]].SetSelect(false);
        end;
      end;

      // hover
      if (High(JukeboxVisibleSongs) > 9) then
      begin
        if InRegion(X, Y, Button[JukeboxSongListUp].GetMouseOverArea) then
            Button[JukeboxSongListUp].SetSelect(true)
        else
            Button[JukeboxSongListUp].SetSelect(false);

        if InRegion(X, Y, Button[JukeboxSongListDown].GetMouseOverArea) then
            Button[JukeboxSongListDown].SetSelect(true)
        else
            Button[JukeboxSongListDown].SetSelect(false);
      end;

      if InRegion(X, Y, Button[JukeboxSongListClose].GetMouseOverArea) then
        Button[JukeboxSongListClose].SetSelect(true)
      else
        Button[JukeboxSongListClose].SetSelect(false);

      //hover fix pin
      if (not SongListVisibleFix) then
      begin
        if InRegion(X, Y, Button[JukeboxSongListFixPin].GetMouseOverArea) then
          Button[JukeboxSongListFixPin].SetSelect(true)
        else
          Button[JukeboxSongListFixPin].SetSelect(false);
      end;

      if InRegion(X, Y, Button[JukeboxSongListOrder].GetMouseOverArea) then
        Button[JukeboxSongListOrder].SetSelect(true)
      else
        Button[JukeboxSongListOrder].SetSelect(not RandomMode);

      if InRegion(X, Y, Button[JukeboxRandomSongList].GetMouseOverArea) then
        Button[JukeboxRandomSongList].SetSelect(true)
      else
        Button[JukeboxRandomSongList].SetSelect(RandomMode);

      if InRegion(X, Y, Button[JukeboxRepeatSongList].GetMouseOverArea) then
        Button[JukeboxRepeatSongList].SetSelect(true)
      else
        Button[JukeboxRepeatSongList].SetSelect(RepeatSongList);

      if InRegion(X, Y, Button[JukeboxPlayPause].GetMouseOverArea) then
        Button[JukeboxPlayPause].SetSelect(true)
      else
        Button[JukeboxPlayPause].SetSelect(Paused);

      if InRegion(X, Y, Button[JukeboxLyric].GetMouseOverArea) then
        Button[JukeboxLyric].SetSelect(true)
      else
        Button[JukeboxLyric].SetSelect(ShowLyrics);

      if InRegion(X, Y, Button[JukeboxOptions].GetMouseOverArea) then
        Button[JukeboxOptions].SetSelect(true)
      else
        Button[JukeboxOptions].SetSelect(false);

      if InRegion(X, Y, Button[JukeboxFindSong].GetMouseOverArea) then
      begin
        Button[JukeboxFindSong].SetSelect(true);
        StartTextInput;
      end
      else
      begin
        Button[JukeboxFindSong].SetSelect(FindSongList);
        SetTextInput(FindSongList);
      end;

    end;
  end;

  if (SongMenuVisible) then
  begin
    //songmenu visible
    if (BtnDown) and (MouseButton = SDL_BUTTON_LEFT) then
    begin
      if InRegion(X, Y, Button[JukeboxSongMenuPlayPause].GetMouseOverArea) then
        Result := ParseInput(SDLK_SPACE, 0, true);

      if InRegion(X, Y, Button[JukeboxSongMenuPrevious].GetMouseOverArea) then
        Result := ParseInput(SDLK_LEFT, 0, true);

      if InRegion(X, Y, Button[JukeboxSongMenuNext].GetMouseOverArea) then
        Result := ParseInput(SDLK_RIGHT, 0, true);

      if InRegion(X, Y, Button[JukeboxSongMenuPlaylist].GetMouseOverArea) then
      begin
        SongMenuVisible := false;
        SongListVisible := true;

        LastTick := SDL_GetTicks();
      end;

      if InRegion(X, Y, Statics[JukeboxStaticSongMenuTimeProgress].GetMouseOverArea) then
      begin
        Time := ((X - Statics[JukeboxStaticSongMenuTimeProgress].Texture.X) * LyricsState.TotalTime)/(Statics[JukeboxStaticSongMenuTimeProgress].Texture.W);

        ChangeTime(Time);
      end;

      // change time
      if InRegion(X, Y, Text[JukeboxTextSongMenuTimeText].GetMouseOverArea) then
      begin
        if (fTimebarMode = High(TTimebarMode)) then
          fTimebarMode := Low(TTimebarMode)
        else
          Inc(fTimebarMode);

        Ini.JukeboxTimebarMode := Ord(fTimebarMode);
        Ini.SaveJukeboxTimebarMode();
      end;

      if InRegion(X, Y, Button[JukeboxSongMenuOptions].GetMouseOverArea) then
      begin
        SongMenuVisible := false;
        SongListVisible := false;
        StopTextInput;

        Button[JukeboxSongMenuOptions].SetSelect(false);

        ScreenJukeboxOptions.Visible := true;

        LastSongOptionsTick := SDL_GetTicks();
      end;
    end
    else
    begin
      // hover
      if InRegion(X, Y, Button[JukeboxSongMenuPlayPause].GetMouseOverArea) then
        Button[JukeboxSongMenuPlayPause].SetSelect(true)
      else
        Button[JukeboxSongMenuPlayPause].SetSelect(Paused);

      if InRegion(X, Y, Button[JukeboxSongMenuPrevious].GetMouseOverArea) then
        Button[JukeboxSongMenuPrevious].SetSelect(true)
      else
        Button[JukeboxSongMenuPrevious].SetSelect(false);

      if InRegion(X, Y, Button[JukeboxSongMenuNext].GetMouseOverArea) then
        Button[JukeboxSongMenuNext].SetSelect(true)
      else
        Button[JukeboxSongMenuNext].SetSelect(false);

      if InRegion(X, Y, Button[JukeboxSongMenuPlaylist].GetMouseOverArea) then
        Button[JukeboxSongMenuPlaylist].SetSelect(true)
      else
        Button[JukeboxSongMenuPlaylist].SetSelect(false);

      if InRegion(X, Y, Button[JukeboxSongMenuOptions].GetMouseOverArea) then
        Button[JukeboxSongMenuOptions].SetSelect(true)
      else
        Button[JukeboxSongMenuOptions].SetSelect(false);
    end
  end;

  if (not(SongListVisible) and not(ScreenJukeboxOptions.Visible) and (SDL_GetTicks - CloseClickTime > MAX_TIME_MOUSE_CLOSE))
    or (not(SongListVisible) and not(ScreenJukeboxOptions.Visible) and (Y <= 5)) then
  begin
    if (SongListVisibleFix) then
    begin
      SongListVisible := true;
    end
    else
    begin
      SongMenuVisible := true;
      LastSongMenuTick := SDL_GetTicks();
    end;
    if MouseButton = SDL_BUTTON_RIGHT then
    begin
      ScreenPopupCheck.ShowPopup('MSG_END_JUKEBOX', OnEscapeJukebox, nil, true)
    end;
  end;
end;

procedure TScreenJukebox.RandomList();
var
  I, RValueI, RValueE: integer;
  tmp: integer;
begin
  LastTick := SDL_GetTicks();

  Button[JukeboxRandomSongList].SetSelect(true);
  Button[JukeboxSongListOrder].SetSelect(false);

  RandomMode := true;
  OrderMode := false;

  for I := 0 to High(JukeboxVisibleSongs) * 2 do
  begin
    RValueI := RandomRange(0, High(JukeboxVisibleSongs) + 1);
    RValueE := RandomRange(0, High(JukeboxVisibleSongs) + 1);

    tmp := JukeboxVisibleSongs[RValueI];
    JukeboxVisibleSongs[RValueI] := JukeboxVisibleSongs[RValueE];
    JukeboxVisibleSongs[RValueE] := tmp;

    if (RValueI = CurrentSongList) then
      CurrentSongList := RValueE
    else
    begin
      if (RValueE = CurrentSongList) then
        CurrentSongList := RValueI;
    end;
  end;
end;

procedure TScreenJukebox.ChangeOrderList();
begin
  LastTick := SDL_GetTicks();

  Button[JukeboxRandomSongList].SetSelect(false);
  Button[JukeboxSongListOrder].SetSelect(true);

  if (OrderMode) then
  begin
    if (OrderType < 5) then
    begin
      OrderType := OrderType + 1;
    end
    else
      OrderType := 1;
  end;

  RandomMode := false;
  OrderMode := true;

  SongListSort(OrderType);
  SyncCurrentIndex;
end;

procedure TScreenJukebox.ChangeSongPosition(Start, Final: integer);
var
  I_Index, F_Index: integer;
  ALength: Cardinal;
  TailElements: Cardinal;
begin
  LastTick := SDL_GetTicks();

  I_Index := Start;
  F_Index := Final;
  ALength := Length(JukeboxVisibleSongs);

  //insert
  Assert(F_Index <= ALength);
  SetLength(JukeboxVisibleSongs, ALength + 1);
  Finalize(JukeboxVisibleSongs[ALength]);
  TailElements := ALength - F_Index;
  if TailElements > 0 then
    Move(JukeboxVisibleSongs[F_Index], JukeboxVisibleSongs[F_Index + 1], SizeOf(I_Index) * TailElements);
  Initialize(JukeboxVisibleSongs[F_Index]);
  JukeboxVisibleSongs[F_Index] := JukeboxVisibleSongs[I_Index];

  ALength := Length(JukeboxVisibleSongs);

  //delete
  Assert(ALength > 0);
  Assert(I_Index < ALength);
  Finalize(JukeboxVisibleSongs[I_Index]);
  TailElements := ALength - I_Index;
  if TailElements > 0 then
    Move(JukeboxVisibleSongs[I_Index + 1], JukeboxVisibleSongs[I_Index], SizeOf(F_Index) * TailElements);
  Initialize(JukeboxVisibleSongs[ALength - 1]);
  SetLength(JukeboxVisibleSongs, ALength - 1);
end;

procedure TScreenJukebox.ChangeTime(Time: real);
begin
  LastTick := SDL_GetTicks();

  AudioPlayback.Position := Time;

  if (Assigned(fCurrentVideo)) then
    fCurrentVideo.Position := CurrentSong.VideoGAP + CurrentSong.Start + Time;

  // correct lyric timer
  LyricsState.StartTime := CurrentSong.GAP + Time;
  LyricsState.SetCurrentTime(Time);

  // main text
  Lyrics.Clear();

end;


// method for input parsing. if false is returned, getnextwindow
// should be checked to know the next window to load;

function TScreenJukebox.ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
  PressedDown: boolean): boolean;
var
  SDL_ModState: word;
  tmp: integer;
begin
  Result := true;

  // ui-v2: display settings card takes all keys while open
  if FDisplayVisible then
  begin
    if PressedDown then
      Result := ParseDisplayInput(PressedKey);
    Exit;
  end;

  //Jukebox Screen Extensions (Options)
  if (ScreenJukeboxOptions.Visible) then
  begin
    Result := ScreenJukeboxOptions.ParseInput(PressedKey, CharCode, PressedDown);
    Exit;
  end;

  SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT +
    KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT + KMOD_RALT);

  // ui-v2: any key brings the player bar up for a moment
  if PressedDown and not SongListVisible then
    ShowBar;

  if (PressedDown) then
  begin // key down
    // check normal keys

    if (FindSongList) and (SongListVisible) then
    begin
      if (IsPrintableChar(CharCode)) then
      begin

        {if not (FindSongList) then
        begin
          UpperLetter := UCS4UpperCase(CharCode);

          GoToSongList(UpperLetter);
        end
        else
        begin}

        LastTick := SDL_GetTicks();

        Button[JukeboxFindSong].Text[0].Text := Button[JukeboxFindSong].Text[0].Text +
                                          UCS4ToUTF8String(CharCode);

        Filter := Button[JukeboxFindSong].Text[0].Text;
        FilterSongList(Filter);
        Exit;
        {end;}
      end
    end
    else
    begin
      case PressedKey of
        SDLK_Q:
        begin
          // when not ask before exit then finish now
          if (Ini.AskbeforeDel <> 1) then
            Finish
          // else just pause and let the popup make the work
          else if not Paused then
            Pause;

          Result := false;
          Exit;
        end;

        // show visualization
        SDLK_V:
        begin
          if fShowWebcam then
          begin
            Webcam.Release;
            fShowWebCam:=false;
          end;
          if ((fShowBackground = true) and (Ini.VideoEnabled = 1) and CurrentSong.Video.IsSet())
                               or (fShowVisualization and not CurrentSong.Background.IsSet()) then //switch to video
          begin
            Log.LogStatus('decided to switch to video', 'UScreenSing.ParseInput');
            fShowBackground := false;
		    fShowWebCam := false;
            fCurrentVideo := nil;
            fShowVisualization := false;
            fCurrentVideo := fVideoClip;
            if (Assigned(fCurrentVideo)) then
               fCurrentVideo.Position := CurrentSong.VideoGAP + AudioPlayback.Position;
            Log.LogStatus('finished switching to video', 'UScreenSing.ParseInput');
          end
          else
          begin
            if fShowVisualization and CurrentSong.Background.IsSet() then
            begin //switch to Background only
              Log.LogStatus('decided to switch to background', 'UScreenSing.ParseInput');
              fShowBackground := true;
			  fShowWebCam := false;
              fCurrentVideo := nil;
              fShowVisualization := false;
              Log.LogStatus('finished switching to background', 'UScreenSing.ParseInput');
            end
            else
            begin //Video is currently visible, change to visualization
              Log.LogStatus('decided to switch to visualization', 'UScreenSing.ParseInput');
              fShowVisualization := true;
			  fShowWebCam := false;
              fCurrentVideo := Visualization.Open(PATH_NONE);
              fCurrentVideo.play;
              Log.LogStatus('finished switching to visualization', 'UScreenSing.ParseInput');
            end;
          end;
          Exit;
        end;

        // show Webcam
      SDLK_W:
      begin
        if (fShowWebCam = false) then
        begin
          fCurrentVideo := nil;
          fShowVisualization := false;
          fShowBackground := false;
          Webcam.Restart;
          if (Webcam.Capture = nil) then
          begin
            fShowWebCam := false;
            fShowBackground := true;
            ScreenPopupError.ShowPopup(Language.Translate('SING_OPTIONS_WEBCAM_NO_WEBCAM'))
          end
          else
            fShowWebCam := true;
        //  ChangeEffectLastTick := SDL_GetTicks;
        //  SelectsS[WebcamParamsSlide].Visible := true;
        //  LastTickFrame := SDL_GetTicks;
        end
        else
        begin
          Webcam.Release;
          fShowWebCam:=false;
        end;

        Exit;
      end;

        // allow search for songs
        SDLK_J:
        begin
          if (SongListVisible) then
          begin
            LastTick := SDL_GetTicks();
            FindSongList := not FindSongList;
            if (Filter = '') and (FindSongList) then
                Button[JukeboxFindSong].Text[0].Text := '';
            Button[JukeboxFindSong].SetSelect(FindSongList);
            SetTextInput(FindSongList);
            if FindSongList then
              FilterSongList(Filter)
            else
              FilterSongList('');
            Exit;
          end
          else
          begin
            SongListVisible := true;
            LastTick := SDL_GetTicks();
            FindSongList := true;
            if (Filter = '') then
                Button[JukeboxFindSong].Text[0].Text := '';
            Button[JukeboxFindSong].SetSelect(FindSongList);
            SetTextInput(FindSongList);
            FilterSongList(Filter);
            Exit;
          end;
        end;

        // skip intro
        SDLK_S:
        begin
          if (AudioPlayback.Position < CurrentSong.gap / 1000 - 6) then
          begin
            AudioPlayback.SetPosition(CurrentSong.gap / 1000.0 - 5.0);
              if (Assigned(fCurrentVideo)) then
                 fCurrentVideo.Position := CurrentSong.VideoGAP + CurrentSong.Start + (CurrentSong.gap / 1000.0 - 5.0);
          end;
          Exit;
        end;

        // pause
        SDLK_P:
        begin
          Pause;
          Exit;
        end;

        SDLK_R:
        begin
          if (SongListVisible) then
          begin
            RandomList();
          end;
        end;

        // toggle time display
        SDLK_T:
        begin
          LastTick := SDL_GetTicks();

          if (fTimebarMode = High(TTimebarMode)) then
            fTimebarMode := Low(TTimebarMode)
          else
            Inc(fTimebarMode);

          Ini.JukeboxTimebarMode := Ord(fTimebarMode);
          Ini.SaveJukeboxTimebarMode();

          Exit;
        end;
      end;
     end;

      // check special keys
     case PressedKey of
        SDLK_A:
        begin
          // change aspect ratio
          if (SDL_ModState = KMOD_LSHIFT) then
          begin
            if (AspectCorrection = acoCrop) then
              AspectCorrection := acoLetterBox
            else
            begin
              if (AspectCorrection = acoHalfway) then
                AspectCorrection := acoCrop
              else
              begin
                if (AspectCorrection = acoLetterBox) then
                  AspectCorrection := acoHalfway;
              end;
            end;
          end;
        end;

        SDLK_L:
        begin
          if (SDL_ModState = KMOD_LCTRL) then
          begin
            LastTick := SDL_GetTicks();

            ShowLyrics := not ShowLyrics;
            Button[JukeboxLyric].SetSelect(ShowLyrics);
            Exit;
          end;
        end;

        SDLK_O:
        begin
          if not (FindSongList) or not (SongListVisible) then
          begin
            OpenDisplay;
            Exit;
          end;
        end;

        SDLK_S:
        begin

          if (SongListVisible) and (SDL_ModState = KMOD_LCTRL) then
          begin
            ChangeOrderList();
            Exit;
          end;

        end;

        // repeat songlist
        SDLK_X:
        begin
          if (SDL_ModState = KMOD_LCTRL) then
          begin
            LastTick := SDL_GetTicks();

            RepeatSongList := not RepeatSongList;
            Button[JukeboxRepeatSongList].SetSelect(RepeatSongList);
            Exit;
          end;
        end;

        SDLK_F:
        begin

          if (SongListVisible) and (SDL_ModState = KMOD_LCTRL) then
          begin
            LastTick := SDL_GetTicks();

            FindSongList := not FindSongList;

            if (Filter = '') then
            begin
              if (FindSongList) then
                Button[JukeboxFindSong].Text[0].Text := ''
            end;

            Button[JukeboxFindSong].SetSelect(FindSongList);
            SetTextInput(FindSongList);

            if not (FindSongList) then
            begin
              Button[JukeboxFindSong].Text[0].Selected := false;
              FilterSongList('');
            end
            else
            begin
              Button[JukeboxFindSong].Text[0].Selected := true;
              FilterSongList(Filter);
            end;

            Exit;
          end;
        end;

        SDLK_R:
        begin

          if (SongListVisible) and (SDL_ModState = KMOD_LCTRL) then
          begin
            RandomList();
          end;
        end;

        SDLK_ESCAPE:
        begin
          if (SongListVisible) then
          begin
            SongListVisible := false;
            if FindSongList then
            begin
              FindSongList := false;
              StopTextInput;
            end;
          end
          else
            ScreenPopupCheck.ShowPopup('MSG_END_JUKEBOX', OnEscapeJukebox, nil, false)
        end;

        SDLK_BACKSPACE:
        begin

          if (FindSongList) and (SongListVisible) then
          begin
            LastTick := SDL_GetTicks();
            if (Filter = '') then
            begin
              FindSongList:=false;
              Button[JukeboxFindSong].SetSelect(FindSongList);
              SetTextInput(FindSongList);
              Exit;
            end;
            Button[JukeboxFindSong].Text[0].DeleteLastLetter();
            Filter := Button[JukeboxFindSong].Text[0].Text;
            FilterSongList(Filter);
          end
          else
          begin
            ScreenPopupCheck.ShowPopup('MSG_END_JUKEBOX', OnEscapeJukebox, nil, false)
          end;
        end;

        SDLK_SPACE:
        begin
          if not (FindSongList) then
            Pause;
        end;

        SDLK_TAB:
        begin
          if (SDL_ModState = KMOD_LCTRL) then // change visualization preset
          begin
            if fShowVisualization then
              fCurrentVideo.Position := now; // move to a random position

            if (fShowWebcam) then
            begin
              if (Ini.WebCamEffect < 10) then
                Ini.WebCamEffect := Ini.WebCamEffect + 1
              else
                Ini.WebCamEffect := 0;
            end;
          end
          else // show help popup
            ScreenPopupHelp.ShowPopup();
        end;

        SDLK_RETURN:
        begin
          if (SongListVisible) then
          begin
            LastTick := SDL_GetTicks();
            if (FindSongList) then
            begin
              FindSongList:=false;
              Button[JukeboxFindSong].SetSelect(FindSongList);
              SetTextInput(FindSongList);
            end;
            if (High(JukeboxVisibleSongs) < 0) then
            begin
              FilterSongList('');
            end;
            CurrentSongList := ActualInteraction - 1;
            Finish;
            PlayMusic(CurrentSongList, True);
          end;
        end;

        SDLK_LEFT:
        begin

          if not (SongListVisible) and (CurrentSongList > 0) then
          begin
            CurrentSongList := CurrentSongList - 1;
            PlayMusic(CurrentSongList, false);
          end;

        end;

        SDLK_RIGHT:
        begin

          if not (SongListVisible) and (CurrentSongList < High(JukeboxVisibleSongs)) then
          begin
            CurrentSongList := CurrentSongList + 1;
            PlayMusic(CurrentSongList, false);
          end;

        end;

        SDLK_DELETE:
        begin
          if (SongListVisible) then
          begin
            ScreenPopupCheck.ShowPopup('JUKEBOX_DELETE_SONG', OnDeleteSong, nil, false)
          end;
        end;

        SDLK_PAGEDOWN:
        begin
          PageDown(10);
        end;

        SDLK_PAGEUP:
        begin
          PageUp(10);
        end;

        // up and down could be done at the same time,
        // but i don't want to declare variables inside
        // functions like this one, called so many times

        SDLK_DOWN:
        begin
          if (SongListVisible) then
          begin
            LastTick := SDL_GetTicks();

            if (SDL_ModState = KMOD_LCTRL) and (ActualInteraction < High(JukeboxVisibleSongs)) then
            begin
              Button[JukeboxSongListOrder].SetSelect(false);
              OrderMode := false;

              tmp := JukeboxVisibleSongs[ActualInteraction];
              JukeboxVisibleSongs[ActualInteraction] := JukeboxVisibleSongs[ActualInteraction + 1];
              JukeboxVisibleSongs[ActualInteraction + 1] := tmp;

              if (ActualInteraction + 1 = CurrentSongList) then
                CurrentSongList := CurrentSongList - 1
              else
              begin
                if (ActualInteraction = CurrentSongList) then
                  CurrentSongList := ActualInteraction + 1;
              end;
            end;

            if not(SDL_ModState = KMOD_LSHIFT) and not(SDL_ModState = KMOD_LALT) and (ActualInteraction < High(JukeboxVisibleSongs)) then
            begin
              ActualInteraction := ActualInteraction + 1;

              if (Interaction = 9) then
                ListMin := ListMin + 1
              else
                InteractInc;

            end;
          end;

          if not(SDL_ModState = KMOD_LALT) and not(SDL_ModState = KMOD_LSHIFT) and (not SongListVisible) then
          begin
            SongListVisible := true;
            ActualInteraction := CurrentSongList;
            LastTick := SDL_GetTicks();
          end;

        end;
        SDLK_UP:
        begin
          if (SongListVisible) and (ActualInteraction > 0) then
          begin
            LastTick := SDL_GetTicks();

            if (SDL_ModState = KMOD_LCTRL) and (ActualInteraction > 0) then
            begin
              Button[JukeboxSongListOrder].SetSelect(false);
              OrderMode := false;

              tmp := JukeboxVisibleSongs[ActualInteraction];
              JukeboxVisibleSongs[ActualInteraction] := JukeboxVisibleSongs[ActualInteraction - 1];
              JukeboxVisibleSongs[ActualInteraction - 1] := tmp;

              if (ActualInteraction - 1 = CurrentSongList) then
                CurrentSongList := CurrentSongList + 1
              else
              begin
                if (ActualInteraction = CurrentSongList) then
                  CurrentSongList := ActualInteraction - 1;
              end;
            end;

            if not(SDL_ModState = KMOD_LSHIFT) and not(SDL_ModState = KMOD_LALT) then
            begin
              ActualInteraction := ActualInteraction - 1;

              if (Interaction = 0) then
                ListMin := ListMin - 1
              else
                InteractDec;
            end;
          end;

          if not(SDL_ModState = KMOD_LALT) and not(SDL_ModState = KMOD_LSHIFT) and (not SongListVisible) then
          begin
            SongListVisible := true;
            ActualInteraction := CurrentSongList;
            LastTick := SDL_GetTicks();
          end;

        end;

      end;
    end;
end;

procedure TScreenJukebox.PageDown(N: integer);
begin
  if (SongListVisible) and (High(JukeboxVisibleSongs) > 9) then
  begin
    LastTick := SDL_GetTicks();

    if (ListMin + N + Interaction < High(JukeboxVisibleSongs) - 9) then
    begin
      ActualInteraction := ListMin + N + Interaction;
      ListMin := ListMin + N;
    end
    else
    begin
      ActualInteraction := High(JukeboxVisibleSongs);
      ListMin := High(JukeboxVisibleSongs) - 9;
      Interaction := 9;
    end;
  end;
end;

procedure TScreenJukebox.PageUp(N: integer);
begin
  if (SongListVisible) and (High(JukeboxVisibleSongs) > 9) then
  begin
    LastTick := SDL_GetTicks();

    if (ListMin - N > 0) then
    begin
      ActualInteraction := ListMin - N;
      ListMin := ListMin - N;

      if ListMin < 0 then
        ListMin := 0;
    end
    else
    begin
      ActualInteraction := 0;
      ListMin := 0;
      Interaction := 0;
    end;
  end;
end;

// pause mod
procedure TScreenJukebox.Pause;
begin

  if (not Paused) then  // enable pause
  begin
    // pause time
    Paused := true;

    LyricsState.Pause();

    // pause music
    AudioPlayback.Pause;

    // pause video
    if fCurrentVideo <> nil then
      fCurrentVideo.Pause;

  end
  else              // disable pause
  begin
    LyricsState.Start();

    // play music
    AudioPlayback.Play;

    // video
    if fCurrentVideo <> nil then
      fCurrentVideo.Pause;

    Paused := false;
  end;

  Button[JukeboxSongMenuPlayPause].SetSelect(Paused);
  Button[JukeboxPlayPause].SetSelect(Paused);

end;
// pause mod end

constructor TScreenJukebox.Create;
var
  I, PosY: integer;
begin
  inherited Create;

  SongListVisible := false;
  ListMin := 0;
  ShowLyrics := false;

  RightMbESC := false;

  fShowVisualization := false;
  fShowWebcam := false;
  fShowBackground := false;

  fCurrentVideo := nil;

  LoadFromTheme(Theme.Jukebox);

  Lyrics := TLyricEngine.Create(
      Theme.LyricBar.UpperX, Theme.LyricBar.UpperY, Theme.LyricBar.UpperW, Theme.LyricBar.UpperH,
      Theme.LyricBar.LowerX, Theme.LyricBar.LowerY, Theme.LyricBar.LowerW, Theme.LyricBar.LowerH);

  fLyricsSync := TLyricsSyncSource.Create();
  fMusicSync := TMusicSyncSource.Create();

  //Jukebox Items
  JukeboxStaticTimeProgress       := AddStaticColorRectangle(Theme.Jukebox.StaticTimeProgress);
  JukeboxStaticTimeBackground     := AddStatic(Theme.Jukebox.StaticTimeBackground);
  JukeboxStaticSongBackground     := AddStatic(Theme.Jukebox.StaticSongBackground);
  JukeboxStaticSongListBackground := AddStatic(Theme.Jukebox.StaticSongListBackground);

  JukeboxTextTimeText         := AddText(Theme.Jukebox.TextTimeText);

  PosY := Theme.Jukebox.SongDescription.Y;
  for I := 0 to 9 do
  begin
    Theme.Jukebox.SongDescription.Y := PosY + Theme.Jukebox.SongDescription.H * I;
    SongDescription[I] := AddButton(Theme.Jukebox.SongDescription);
  end;

  SongDescriptionClone := AddButton(Theme.Jukebox.SongDescription);

  Button[SongDescriptionClone].DeSelectTexture.ColR := Theme.Jukebox.SongDescription.ColR;
  Button[SongDescriptionClone].DeSelectTexture.ColG := Theme.Jukebox.SongDescription.ColG;
  Button[SongDescriptionClone].DeSelectTexture.ColB := Theme.Jukebox.SongDescription.ColB;
  Button[SongDescriptionClone].Visible := false;

  SelectColR := Theme.Jukebox.SongDescription.ColR;
  SelectColG := Theme.Jukebox.SongDescription.ColG;
  SelectColB := Theme.Jukebox.SongDescription.ColB;

  JukeboxFindSong := AddButton(Theme.Jukebox.FindSong);
  JukeboxRepeatSongList := AddButton(Theme.Jukebox.RepeatSongList);
  JukeboxSongListOrder := AddButton(Theme.Jukebox.SongListOrder);
  JukeboxRandomSongList := AddButton(Theme.Jukebox.RandomSongList);
  JukeboxLyric := AddButton(Theme.Jukebox.Lyric);
  JukeboxOptions := AddButton(Theme.Jukebox.Options);
  JukeboxSongListClose := AddButton(Theme.Jukebox.SongListClose);
  JukeboxSongListFixPin := AddButton(Theme.Jukebox.SongListFixPin);
  JukeboxPlayPause := AddButton(Theme.Jukebox.SongListPlayPause);

  Button[JukeboxFindSong].Selectable := false;
  Button[JukeboxRepeatSongList].Selectable := false;
  Button[JukeboxSongListOrder].Selectable := false;
  Button[JukeboxRandomSongList].Selectable := false;
  Button[JukeboxLyric].Selectable := false;
  Button[JukeboxSongListClose].Selectable := false;
  Button[JukeboxOptions].Selectable := false;
  Button[JukeboxSongListFixPin].Selectable := false;
  Button[JukeboxPlayPause].Selectable := false;

  Button[JukeboxFindSong].Text[0].Writable := true;

  JukeboxListText  := AddText(Theme.Jukebox.TextListText);
  JukeboxCountText := AddText(Theme.Jukebox.TextCountText);

  StaticCover := AddStaticPosition(Theme.Jukebox.SongCover);

  SetLength(JukeboxStaticActualSongStatic, Length(Theme.Jukebox.StaticActualSongStatics));
  for I := 0 to High(Theme.Jukebox.StaticActualSongStatics) do
  begin
    JukeboxStaticActualSongStatic[I] := AddStatic(Theme.Jukebox.StaticActualSongStatics[i]);
  end;

  JukeboxStaticActualSongCover := AddStaticPosition(Theme.Jukebox.StaticActualSongCover);
  JukeboxTextActualSongArtist := AddText(Theme.Jukebox.TextActualSongArtist);
  JukeboxTextActualSongTitle := AddText(Theme.Jukebox.TextActualSongTitle);

  JukeboxSongListUp := AddButton(Theme.Jukebox.SongListUp);
  JukeboxSongListDown := AddButton(Theme.Jukebox.SongListDown);

  // Jukebox SongMenu Items
  JukeboxSongMenuPlayPause := AddButton(Theme.Jukebox.SongMenuPlayPause);
  JukeboxSongMenuNext      := AddButton(Theme.Jukebox.SongMenuNext);
  JukeboxSongMenuPrevious  := AddButton(Theme.Jukebox.SongMenuPrevious);
  JukeboxSongMenuPlaylist  := AddButton(Theme.Jukebox.SongMenuPlaylist);
  JukeboxSongMenuOptions   := AddButton(Theme.Jukebox.SongMenuOptions);

  Button[JukeboxSongMenuPlaylist].Selectable := false;
  Button[JukeboxSongMenuNext].Selectable := false;
  Button[JukeboxSongMenuPrevious].Selectable := false;
  Button[JukeboxSongMenuPlaylist].Selectable := false;
  Button[JukeboxSongMenuOptions].Selectable := false;

  JukeboxStaticSongMenuTimeProgress   := AddStaticColorRectangle(Theme.Jukebox.StaticSongMenuTimeProgress);
  JukeboxStaticSongMenuTimeBackground := AddStatic(Theme.Jukebox.StaticSongMenuTimeBackground);
  JukeboxTextSongMenuTimeText         := AddText(Theme.Jukebox.SongMenuTextTime);
  JukeboxStaticSongMenuBackground     := AddStatic(Theme.Jukebox.StaticSongMenuBackground);
end;

destructor TScreenJukebox.Destroy;
begin
  Tex_Background.Free;
  inherited;
end;

procedure TScreenJukebox.OnShow;
var
  Col: TRGB;
begin
  inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenJukebox');

  // songmenu
  if (Ini.JukeboxSongMenu = 1) then
    SongListVisibleFix := false
  else
    SongListVisibleFix := true;

  Button[JukeboxSongListFixPin].SetSelect(SongListVisibleFix);

  {**
  * Pause background music
  *}
  SoundLib.PauseBgMusic;

  FadeOut := false;

  Lyrics.UpperLineX := Theme.LyricBarJukebox.UpperX;
  Lyrics.UpperLineY := Theme.LyricBarJukebox.UpperY;
  Lyrics.UpperLineW := Theme.LyricBarJukebox.UpperW;
  Lyrics.UpperLineH := Theme.LyricBarJukebox.UpperH;

  Lyrics.LowerLineX := Theme.LyricBarJukebox.LowerX;
  Lyrics.LowerLineY := Theme.LyricBarJukebox.LowerY;
  Lyrics.LowerLineW := Theme.LyricBarJukebox.LowerW;
  Lyrics.LowerLineH := Theme.LyricBarJukebox.LowerH;

  tmpLyricsUpperY := Lyrics.UpperLineY;
  tmpLyricsLowerY := Lyrics.LowerLineY;

  Lyrics.FontFamily := Ini.JukeboxFont;
  Lyrics.FontStyle := Ini.JukeboxStyle;

  case Ini.JukeboxStyle of
    0, 1: // regular/bold (non-outline) font
    begin
      Lyrics.LineColor_en.R := Skin_FontR;
      Lyrics.LineColor_en.G := Skin_FontG;
      Lyrics.LineColor_en.B := Skin_FontB;
      Lyrics.LineColor_en.A := 1;

      Lyrics.LineColor_dis.R := 0.2;
      Lyrics.LineColor_dis.G := 0.2;
      Lyrics.LineColor_dis.B := 0.2;
      Lyrics.LineColor_dis.A := 1;

      if (Ini.JukeboxSingLineColor = High(UIni.ISingLineColor)) then
        Col := GetJukeboxLyricOtherColor(0)
      else
        Col := GetLyricColor(Ini.JukeboxSingLineColor);

      Lyrics.LineColor_act.R := Col.R; //0.02;
      Lyrics.LineColor_act.G := Col.G; //0.6;
      Lyrics.LineColor_act.B := Col.B; //0.8;
      Lyrics.LineColor_act.A := 1;
    end;
    2: // outline fonts
    begin
      if (Ini.JukeboxSingLineColor = High(UIni.ISingLineColor)) then
        Col := GetJukeboxLyricOtherColor(0)
      else
        Col := GetLyricColor(Ini.JukeboxSingLineColor);
      Lyrics.LineColor_act.R := Col.R;
      Lyrics.LineColor_act.G := Col.G;
      Lyrics.LineColor_act.B := Col.B;
      Lyrics.LineColor_act.A := 1;

      if (Ini.JukeboxActualLineColor = High(UIni.IActualLineColor)) then
        Col := GetJukeboxLyricOtherColor(1)
      else
        Col := GetLyricGrayColor(Ini.JukeboxActualLineColor);
      Lyrics.LineColor_en.R := Col.R;
      Lyrics.LineColor_en.G := Col.G;
      Lyrics.LineColor_en.B := Col.B;
      Lyrics.LineColor_en.A := 1;

      if (Ini.JukeboxNextLineColor = High(UIni.INextLineColor)) then
        Col := GetJukeboxLyricOtherColor(2)
      else
        Col := GetLyricGrayColor(Ini.JukeboxNextLineColor);
      Lyrics.LineColor_dis.R := Col.R;
      Lyrics.LineColor_dis.G := Col.G;
      Lyrics.LineColor_dis.B := Col.B;
      Lyrics.LineColor_dis.A := 1;
    end;
  end; // case

  SongMenuVisible := false;
  SongListVisible := false;
  FDisplayVisible := false;
  FPanelTop := 0;
  JukeboxLoadSettings;

  Log.LogStatus('End', 'OnShow');
end;

procedure TScreenJukebox.OnShowFinish();
begin
  Reset;

  // ui-v2: options picked on the jukebox start screen
  ShowLyrics := JukeboxStartLyrics;
  RepeatSongList := JukeboxStartRepeat;
  if JukeboxStartShuffle and (Length(JukeboxVisibleSongs) > 1) then
  begin
    RandomList();
    CurrentSongList := 0;
  end;

  PlayMusic(0, true);
end;

procedure TScreenJukebox.Play();
begin

    //AudioPlayback.Position := CurrentSong.Start;
    AudioPlayback.Position := LyricsState.GetCurrentTime();

  // set time
  if (CurrentSong.Finish > 0) then
    LyricsState.TotalTime := CurrentSong.Finish / 1000
  else
  begin
      LyricsState.TotalTime := AudioPlayback.Length;
  end;

  LyricsState.UpdateBeats();

  // synchronize music
    if (Ini.SyncTo = Ord(stLyrics)) then
      AudioPlayback.SetSyncSource(fLyricsSync)
    else
      AudioPlayback.SetSyncSource(nil);

    // synchronize lyrics (do not set this before AudioPlayback is initialized)
    if (Ini.SyncTo = Ord(stMusic)) then
      LyricsState.SetSyncSource(fMusicSync)
    else
      LyricsState.SetSyncSource(nil);

  // start lyrics
  LyricsState.Start(true);

  // start music
    AudioPlayback.Play();

  // start timer
  CountSkipTimeSet;

  LastTick := SDL_GetTicks();
  LastTickChangeSong := SDL_GetTicks();
  LyricsStart := false;

end;

procedure TScreenJukebox.OnHide;
begin
  FreeAndNil(Tex_Background);
  if fShowWebcam then
        begin
          Webcam.Release;
          fShowWebCam:=false;
        end;
  Background.OnFinish;
  //Display.SetCursor;
end;

function TScreenJukebox.FinishedMusic: boolean;
begin
    Result := AudioPlayback.Finished;

end;

function TScreenJukebox.Draw: boolean;
var
  DisplayTime:  real;
  DisplayPrefix: string;
  DisplayMin:   integer;
  DisplaySec:   integer;
  CurLyricsTime: real;
  VideoFrameTime: Extended;
begin
  Renderer.ClearFrameBuffer(CLEAR_COLOR or CLEAR_DEPTH);
  Background.Draw;

  // draw background picture (if any, and if no visualizations)
  // when we don't check for visualizations the visualizations would
  // be overdrawn by the picture when {UNDEFINED UseTexture} in UVisualizer
  if (not fShowVisualization) or (fShowBackground) then
    SingDrawJukeboxBackground;

  if (fShowWebCam) then
    SingDrawWebCamFrame;


  // retrieve current lyrics time, we have to store the value to avoid
  // that min- and sec-values do not match
  CurLyricsTime := LyricsState.GetCurrentTime();

  // retrieve time for timebar text
  case (fTimebarMode) of
    tbmRemaining: begin
      DisplayTime := LyricsState.TotalTime - CurLyricsTime;
      DisplayPrefix := '-';
    end;
    tbmTotal: begin
      DisplayTime := LyricsState.TotalTime;
      DisplayPrefix := '#';
    end;
    else begin
      DisplayTime := CurLyricsTime;
      DisplayPrefix := '';
    end;
  end;

  DisplayMin := Round(DisplayTime) div 60;
  DisplaySec := Round(DisplayTime) mod 60;
  Text[JukeboxTextTimeText].Text := Format('%s%.2d:%.2d', [DisplayPrefix, DisplayMin, DisplaySec]);
  Text[JukeboxTextSongMenuTimeText].Text := Format('%s%.2d:%.2d', [DisplayPrefix, DisplayMin, DisplaySec]);

  // update and draw movie
  if Assigned(fCurrentVideo) and (not fShowWebcam) then
  begin
    // Just call this once
    // when Screens = 2
    if (ScreenAct = 1) then
    begin
      if (ShowFinish) then
      begin
        // everything is setup, determine the current position
        VideoFrameTime := CurrentSong.VideoGAP + LyricsState.GetCurrentTime();
      end
      else
      begin
        // Important: do not yet start the triggered timer by a call to
        // LyricsState.GetCurrentTime()
        VideoFrameTime := CurrentSong.VideoGAP;
      end;
      try
         fCurrentVideo.GetFrame(VideoFrameTime);
      except
      end;
    end;

    // ui-v2: the display settings choose how the video fits the screen
    case JukeboxFit of
      1: fCurrentVideo.AspectCorrection := acoLetterBox;
      2: fCurrentVideo.AspectCorrection := acoHalfway;
    else
      fCurrentVideo.AspectCorrection := acoCrop;
    end;
    fCurrentVideo.SetScreen(ScreenAct);
    fCurrentVideo.Draw;
    //DrawBlackBars();
  end;

  // ui-v2: lyrics are drawn by DrawModern below
  //SingDrawJukebox;

  // check for music finish
  //Log.LogError('Check for music finish: ' + BoolToStr(Music.Finished) + ' ' + FloatToStr(LyricsState.CurrentTime*1000) + ' ' + IntToStr(CurrentSong.Finish));
  if ShowFinish then
  begin
    if (not FinishedMusic) and
       ((CurrentSong.Finish = 0) or
        (LyricsState.GetCurrentTime() * 1000 <= CurrentSong.Finish)) then
    begin
      // analyze song if not paused
      if (not Paused) then
      begin
        SingJukebox(Self);
      end;
    end
    else
    begin
      if (not FadeOut) and (Screens=1) or (ScreenAct=2) then
      begin
        Finish;
      end;
    end;
  end;

  // ui-v2: Midnight overlays (lyrics, player bar, up next list, display card)
  if (ScreenAct = 1) then
    DrawModern;

  if Paused = true then
     SDL_Delay(33);
  Result := true;
end;

procedure TScreenJukebox.Finish;
begin
  AudioInput.CaptureStop;
  AudioPlayback.Stop;
  AudioPlayback.SetSyncSource(nil);

  Lyrics.UpperLineY := tmpLyricsUpperY;
  Lyrics.LowerLineY := tmpLyricsLowerY;

  LyricsState.Stop();
  LyricsState.SetSyncSource(nil);

  // close video files
  fVideoClip := nil;
  fCurrentVideo := nil;

  SetFontItalic(false);

  if (CurrentSongList = High(JukeboxVisibleSongs)) then
  begin
    if (RepeatSongList) then
    begin
      // resyart playlist
      CurrentSongList := 0;
      CatSongs.Selected := JukeboxVisibleSongs[CurrentSongList];
      PlayMusic(CurrentSongList, false);
    end
    else
    begin
      FadeTo(@ScreenMain);
    end;
  end
  else
  begin
    CurrentSongList := CurrentSongList + 1;

    CatSongs.Selected := JukeboxVisibleSongs[CurrentSongList];

    PlayMusic(CurrentSongList, false);
  end;
end;

 // Called on sentence change
 // SentenceIndex: index of the new active sentence
procedure TScreenJukebox.OnSentenceChange(SentenceIndex: cardinal);
begin
  // fill lyrics queue and set upper line to the current sentence
  while (Lyrics.GetUpperLineIndex() < SentenceIndex) or
    (not Lyrics.IsQueueFull) do
  begin
    // add the next line to the queue or a dummy if no more lines are available
    if (Lyrics.LineCounter <= High(CurrentSong.Tracks[0].Lines)) then
      Lyrics.AddLine(@CurrentSong.Tracks[0].Lines[Lyrics.LineCounter])
    else
      Lyrics.AddLine(nil);
  end;

end;

function TLyricsSyncSource.GetClock(): real;
begin
  Result := LyricsState.GetCurrentTime();
end;

function TMusicSyncSource.GetClock(): real;
begin
    Result := AudioPlayback.Position;
end;

procedure TScreenJukebox.AddSongToJukeboxList(ID: integer);
var
  I: integer;
  SongExist: boolean;
begin
  if (not CatSongs.Song[ID].Main) then
  begin
    SongExist := false;
    for I := 0 to High(JukeboxSongsList) do
    begin
      if (JukeboxSongsList[I] = ID) then
        SongExist := true;
    end;

    if (not SongExist) then
    begin
      SetLength(JukeboxSongsList, Length(JukeboxSongsList) + 1);
      JukeboxSongsList[High(JukeboxSongsList)] := ID;

      SetLength(JukeboxVisibleSongs, Length(JukeboxVisibleSongs) + 1);
      JukeboxVisibleSongs[High(JukeboxVisibleSongs)] := ID;
    end;
  end;
end;

procedure TScreenJukebox.DrawSongInfo();
var
  I: integer;
  Alpha: real;
  CurrentTick: integer;
begin

  if (not(SongListVisible) and not(ScreenJukeboxOptions.Visible) and (ScreenAct = 1)) or (ScreenAct = 2) then
  begin
    CurrentTick := SDL_GetTicks() - LastTickChangeSong;

    if (CurrentTick < MAX_TIME_SONGDESC) then
      Alpha := 0
    else
      Alpha := (CurrentTick - MAX_TIME_SONGDESC)/MAX_TIME_FADESONGDESC;

    if (CurrentTick - MAX_TIME_SONGDESC < MAX_TIME_FADESONGDESC) then
    begin
      for I := 0 to High(Theme.Jukebox.StaticActualSongStatics) do
      begin
        Statics[JukeboxStaticActualSongStatic[I]].Texture.Alpha := 1 - Alpha;
        Statics[JukeboxStaticActualSongStatic[I]].Draw;
      end;

      Statics[JukeboxStaticActualSongCover].Texture.Alpha := 1 - Alpha;
      Statics[JukeboxStaticActualSongCover].Draw;

      Text[JukeboxTextActualSongArtist].Alpha := 1 - Alpha;
      Text[JukeboxTextActualSongArtist].Draw;

      Text[JukeboxTextActualSongTitle].Alpha := 1 - Alpha;
      Text[JukeboxTextActualSongTitle].Draw;
    end;
  end;

end;

procedure TScreenJukebox.PlayMusic(ID: integer; ShowList: boolean);
var
  Index:  integer;
  VideoFile, BgFile: IPath;
  success: boolean;
  Max: integer;
begin

  // background texture (garbage disposal)
  FreeAndNil(Tex_Background);

  try
    if high(JukeboxVisibleSongs) < ID then
       ID:=0;
    if high(JukeboxVisibleSongs) < 0 then
       Finish;
    CurrentSong := CatSongs.Song[JukeboxVisibleSongs[ID]];
    Text[JukeboxTextActualSongArtist].Text := CurrentSong.Artist;
    Text[JukeboxTextActualSongTitle].Text := CurrentSong.Title;

  Button[JukeboxSongMenuPlaylist].SetSelect(false);
  Paused := false;

  // Cover
  RefreshCover;

  // reset video playback engine
  fVideoClip := nil;
  fCurrentVideo := nil;

  AspectCorrection := acoLetterBox;

  fTimebarMode := TTimebarMode(Ini.JukeboxTimebarMode);

  // FIXME: bad style, put the try-except into loadsong() and not here
  try
    success := CurrentSong.Analyse and CurrentSong.LoadSong(false);
  except
    success := false;
  end;

  if (not success) then
  begin
    // error loading song -> go back to previous screen and show some error message
    Display.AbortScreenChange;
    // select new song in party mode
    if (Length(CurrentSong.LastError) > 0) then
      ScreenPopupError.ShowPopup(Format(Language.Translate(CurrentSong.LastError), [CurrentSong.ErrorLineNo]))
    else
      ScreenPopupError.ShowPopup(Language.Translate('ERROR_CORRUPT_SONG'));
    // FIXME: do we need this?
    CurrentSong.Path := CatSongs.Song[CatSongs.Selected].Path;
    Exit;
  end;

  AudioPlayback.Open(CurrentSong.Path.Append(CurrentSong.Audio),nil);
  AudioPlayback.SetVolume(1.0);

  {*
   * == Background ==
   * We have four types of backgrounds:
   *   + Blank        : Nothing has been set, this is our fallback
   *   + Picture      : Picture has been set, and exists - otherwise we fallback
   *   + Video        : Video has been set, and exists - otherwise we fallback
   *   + Visualization: + Off        : No visualization
   *                    + WhenNoVideo: Overwrites blank and picture
   *                    + On         : Overwrites blank, picture and video
   *}

  {*
   * set background to: video
   *}
  fShowVisualization := false;

  VideoFile := CurrentSong.Path.Append(CurrentSong.Video);

  if (Ini.VideoEnabled = 1) and CurrentSong.Video.IsSet() and VideoFile.IsFile then
  begin
    fVideoClip := VideoPlayback.Open(VideoFile);
    fCurrentVideo := fVideoClip;
    if (fVideoClip <> nil) then
    begin
      fCurrentVideo.Position := CurrentSong.VideoGAP + CurrentSong.Start;
      //fCurrentVideo.Play;
    end;
  end;

  {*
   * set background to: picture
   *}
  //if (CurrentSong.Background.IsSet) and (fVideoClip = nil)
  //  and (TVisualizerOption(Ini.VisualizerOption) = voOff)  then
  if (CurrentSong.Background.IsSet) then
  begin
    BgFile := CurrentSong.Path.Append(CurrentSong.Background);
    try
      Tex_Background := Renderer.LoadTexture(BgFile);
    except
      Log.LogError('Background could not be loaded: ' + BgFile.ToNative);
      FreeAndNil(Tex_Background);
    end
  end
  else
  begin
    FreeAndNil(Tex_Background);
  end;

  {*
   * set background to: visualization (Overwrites all)
   *}
  //if (TVisualizerOption(Ini.VisualizerOption) in [voOn]) then
  if (not fShowWebcam) and (TVisualizerOption(Ini.VisualizerOption) in [voOn]) then
  begin
    fShowVisualization := true;
    fShowBackground := false;
    fCurrentVideo := Visualization.Open(PATH_NONE);
    if (fCurrentVideo <> nil) then
      fCurrentVideo.Play;
  end;

  {*
   * set background to: visualization (Videos are still shown)
   *}
  //if ((TVisualizerOption(Ini.VisualizerOption) in [voWhenNoVideo]) and
  //   (fVideoClip = nil)) then
  if (not fShowWebcam) and ((TVisualizerOption(Ini.VisualizerOption) in [voWhenNoVideo]) and
      (fVideoClip = nil)) then
  begin
    fShowVisualization := true;
    fShowBackground := false;
    fCurrentVideo := Visualization.Open(PATH_NONE);
    if (fCurrentVideo <> nil) then
      fCurrentVideo.Play;
  end;

  // load options
  LoadJukeboxSongOptions();

  // prepare lyrics timer
  LyricsState.Reset();

  LyricsState.SetCurrentTime(CurrentSong.Start);
  LyricsState.StartTime := CurrentSong.Gap;
  if (CurrentSong.Finish > 0) then
    LyricsState.TotalTime := CurrentSong.Finish / 1000
  else
  begin
    LyricsState.TotalTime := AudioPlayback.Length;
  end;

  LyricsState.UpdateBeats();

  // main text
  Lyrics.Clear(CurrentSong.BPM);

  // initialize lyrics by filling its queue
  while (not Lyrics.IsQueueFull) and
        (Lyrics.LineCounter <= High(CurrentSong.Tracks[0].Lines)) do
  begin
    Lyrics.AddLine(@CurrentSong.Tracks[0].Lines[Lyrics.LineCounter]);
  end;

  Max := 9;

  if (High(JukeboxVisibleSongs) < 9) then
    Max := High(JukeboxVisibleSongs);

  for Index := 0 to 9 do
    Button[SongDescription[Index]].Selectable := false;

  for Index := 0 to Max do
  begin
    Button[SongDescription[Index]].Visible := true;
    Button[SongDescription[Index]].Selectable := true;
  end;

  Button[JukeboxFindSong].Visible := true;
  Button[JukeboxRepeatSongList].Visible := true;
  Button[JukeboxSongListOrder].Visible := true;
  Button[JukeboxRandomSongList].Visible := true;
  Button[JukeboxLyric].Visible := true;
  Button[JukeboxSongListUp].Visible := true;
  Button[JukeboxSongListDown].Visible := true;
  Button[JukeboxSongListClose].Visible := true;
  Button[JukeboxOptions].Visible := true;
  Button[JukeboxPlayPause].Visible := true;

  CurrentSongID := JukeboxVisibleSongs[CurrentSongList];

  // ui-v2: picking a song closes the up next list; the player bar shows
  // what's now playing
  if ShowList then
    SongListVisible := false;
  ShowBar;

  Play();
  except
    ;
  end;
end;

procedure TScreenJukebox.RefreshCover();
var
  CoverPath: IPath;
begin

  CoverPath := CurrentSong.Path.Append(CurrentSong.Cover);

  Statics[StaticCover].Texture.Free;
  Statics[StaticCover].Texture := Renderer.GetTexture(CoverPath, TEXTURE_TYPE_PLAIN, 0);

  if (Statics[StaticCover].Texture = nil) then
    Statics[StaticCover].Texture := Renderer.GetTexture(Skin.GetTextureFileName('SongCover'), TEXTURE_TYPE_PLAIN, 0);

  Statics[StaticCover].Texture.X := Theme.Jukebox.SongCover.X;
  Statics[StaticCover].Texture.Y := Theme.Jukebox.SongCover.Y;
  Statics[StaticCover].Texture.W := Theme.Jukebox.SongCover.W;
  Statics[StaticCover].Texture.H := Theme.Jukebox.SongCover.H;
  Statics[StaticCover].Texture.Alpha := 0.7;

  Statics[JukeboxStaticActualSongCover].Texture.Free;
  Statics[JukeboxStaticActualSongCover].Texture := Statics[StaticCover].Texture.Clone;
  Statics[JukeboxStaticActualSongCover].Texture.X := Theme.Jukebox.StaticActualSongCover.X;
  Statics[JukeboxStaticActualSongCover].Texture.Y := Theme.Jukebox.StaticActualSongCover.Y;
  Statics[JukeboxStaticActualSongCover].Texture.W := Theme.Jukebox.StaticActualSongCover.W;
  Statics[JukeboxStaticActualSongCover].Texture.H := Theme.Jukebox.StaticActualSongCover.H;
  Statics[JukeboxStaticActualSongCover].Texture.Alpha := 1;
end;

procedure TScreenJukebox.DrawPlaylist;
var
  Report: string;
  I, J, Max: integer;
  SongDesc, Artist, Title, TimeString: UTF8String;
  CurrentTick: integer;
begin
  CurrentTick := SDL_GetTicks() - LastTick;

  if ((SongListVisibleFix) or (CurrentTick < MAX_TIME_PLAYLIST)) then
  begin
    SongMenuVisible := false;

    Statics[JukeboxStaticTimeBackground].Draw;
    Statics[JukeboxStaticTimeProgress].Draw;
    Statics[JukeboxStaticSongListBackground].Draw;

    Statics[StaticCover].Draw;

    Text[JukeboxTextTimeText].Draw;

    Button[JukeboxSongListUp].Draw;
    Button[JukeboxSongListDown].Draw;

    Max := 9;
    if (High(JukeboxVisibleSongs) < 9) then
      Max := High(JukeboxVisibleSongs);

    if (Max < 0) then
      ActualInteraction := -1;

    Text[JukeboxCountText].Text := IntToStr(ActualInteraction + 1) + '/' + IntToStr(length(JukeboxVisibleSongs));

    Text[JukeboxListText].Draw;
    Text[JukeboxCountText].Draw;

    Button[JukeboxFindSong].Draw;
    Button[JukeboxSongListOrder].Draw;
    Button[JukeboxRepeatSongList].Draw;
    Button[JukeboxRandomSongList].Draw;
    Button[JukeboxLyric].Draw;
    Button[JukeboxSongListClose].Draw;
    Button[JukeboxOptions].Draw;
    Button[JukeboxSongListFixPin].Draw;
    Button[JukeboxPlayPause].Draw;

    for I := 0 to 9 do
    begin
      try
        Button[SongDescription[I]].Visible := true;

        if (I <= Max) then
        begin
          Button[SongDescription[I]].Selectable := true;
          Artist := CatSongs.Song[JukeboxVisibleSongs[I + ListMin]].Artist;
          Title := CatSongs.Song[JukeboxVisibleSongs[I + ListMin]].Title;

          if (OrderType = 2) then
            SongDesc := Title + ' - ' + Artist
          else
            SongDesc := Artist + ' - ' + Title;
        end
        else
        begin
          Button[SongDescription[I]].Selectable := false;
          SongDesc := '';
          TimeString := '';
        end;

        if (Max > -1) then
        begin
          if (JukeboxVisibleSongs[I + ListMin] = CurrentSongID) and (not Button[SongDescription[I]].Selected) then
          begin
            Button[SongDescription[I]].Text[0].ColR := SelectColR;
            Button[SongDescription[I]].Text[0].ColG := SelectColG;
            Button[SongDescription[I]].Text[0].ColB := SelectColB;

            Button[SongDescription[I]].Text[1].ColR := SelectColR;
            Button[SongDescription[I]].Text[1].ColG := SelectColG;
            Button[SongDescription[I]].Text[1].ColB := SelectColB;
          end
          else
          begin
            Button[SongDescription[I]].Text[0].ColR := 1;
            Button[SongDescription[I]].Text[0].ColG := 1;
            Button[SongDescription[I]].Text[0].ColB := 1;

            Button[SongDescription[I]].Text[1].ColR := 1;
            Button[SongDescription[I]].Text[1].ColG := 1;
            Button[SongDescription[I]].Text[1].ColB := 1;
          end;
        end
        else
          Interaction := -1;

        Button[SongDescription[I]].Text[0].Text := SongDesc;
        Button[SongDescription[I]].Text[1].Text := TimeString;
        Button[SongDescription[I]].Draw;
      except
        on E : Exception do
        begin
          Report := 'Drawing of a jukebox entry failed. Check your theme files.' + LineEnding +
          'Stacktrace:' + LineEnding;
          if E <> nil then
          begin
	    Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
	    'Message: ' + E.Message + LineEnding;
          end;
          Report := Report + BackTraceStrFunc(ExceptAddr);
          for J := 0 to ExceptFrameCount - 1 do
          begin
	    Report := Report + LineEnding + BackTraceStrFunc(ExceptFrames[J]);
          end;
          Log.LogWarn(Report, 'UScreenJukebox.DrawPlaylist');
        end;
      end;
    end;
  end
  else
    SongListVisible := false;

end;

procedure TScreenJukebox.DrawSongMenu;
var
  CurrentTick: integer;
begin
  CurrentTick := SDL_GetTicks() - LastSongMenuTick;

  if (CurrentTick < MAX_TIME_SONGMENU) then
  begin
    Statics[JukeboxStaticSongMenuTimeBackground].Draw;
    Statics[JukeboxStaticSongMenuTimeProgress].Draw;
    Statics[JukeboxStaticSongMenuBackground].Draw;

    Text[JukeboxTextSongMenuTimeText].Draw;

    Button[JukeboxSongMenuPlaylist].Draw;
    Button[JukeboxSongMenuOptions].Draw;
    Button[JukeboxSongMenuNext].Draw;
    Button[JukeboxSongMenuPrevious].Draw;
    Button[JukeboxSongMenuPlayPause].Draw;
  end
  else
    SongMenuVisible := false;
end;

procedure TScreenJukebox.LoadJukeboxSongOptions();
var
  Opts: TSongOptions;
begin

  Opts := DataBase.GetSongOptions(CurrentSong);

  if (Opts = nil) then
  begin
    ScreenJukeboxOptions.LoadDefaultOptions;
  end
  else
  begin

    if (Opts.LyricSingFillColor = '') then
    begin
      ScreenJukeboxOptions.LoadDefaultOptions;
      Exit;
    end;

    ScreenJukeboxOptions.LoadSongOptions(Opts);
  end;
end;

{ =====================================================================
  ui-v2: Midnight jukebox
  - the video fills the screen; lyrics read along (nobody is scored)
  - a player bar slides up on any key or mouse move and hides again
  - "Up next" list as a side panel (search, sort, shuffle, pick a song)
  - display card: video fit, lyric position, shade and colours
  ===================================================================== }

const
  JB_PAD     = 32;
  JB_BAR_H   = 96;
  JB_PANEL_W = 480;
  JB_SHOW_MS = 4000;
  JB_ROWS    = 8;
  JB_ROW_H   = 56;

  JSungCols: array[0..4] of cardinal = ($FF3EB5, $7CC4FF, $FF8A5B, $F5C542, $D4FF4F);
  JTodoCols: array[0..4] of cardinal = ($F2F3F5, $FFE8A3, $BFE6FF, $D8C8FF, $C9F2D6);
  JNextCols: array[0..4] of cardinal = ($A9ADB8, $6E7380, $8FA3BF, $B3A08C, $9DB39A);

var
  JSettingsLoaded: boolean = false;

function JClamp(V, Lo, Hi: integer): integer;
begin
  if (V < Lo) then
    Result := Lo
  else if (V > Hi) then
    Result := Hi
  else
    Result := V;
end;

procedure JukeboxLoadSettings;
var
  F: TIniFile;
begin
  if JSettingsLoaded then
    Exit;
  JSettingsLoaded := true;
  try
    F := TIniFile.Create(Ini.Filename.ToNative);
    try
      JukeboxFit      := JClamp(F.ReadInteger('JukeboxUI', 'VideoFit', 0), 0, 2);
      JukeboxLyricPos := JClamp(F.ReadInteger('JukeboxUI', 'LyricPosition', 1), 1, 3);
      JukeboxShade    := JClamp(F.ReadInteger('JukeboxUI', 'Shade', 6), 0, 10);
      JukeboxColSung  := JClamp(F.ReadInteger('JukeboxUI', 'SungColour', 0), 0, 4);
      JukeboxColTodo  := JClamp(F.ReadInteger('JukeboxUI', 'TodoColour', 0), 0, 4);
      JukeboxColNext  := JClamp(F.ReadInteger('JukeboxUI', 'NextColour', 0), 0, 4);
      JukeboxStartShuffle := F.ReadBool('JukeboxUI', 'Shuffle', false);
      JukeboxStartLyrics  := F.ReadBool('JukeboxUI', 'Lyrics', true);
      JukeboxStartRepeat  := F.ReadBool('JukeboxUI', 'Repeat', false);
    finally
      F.Free;
    end;
  except
    on E: Exception do
      Log.LogWarn('Could not read jukebox settings: ' + E.Message, 'JukeboxLoadSettings');
  end;
end;

procedure JukeboxSaveSettings;
var
  F: TIniFile;
begin
  try
    F := TIniFile.Create(Ini.Filename.ToNative);
    try
      F.WriteInteger('JukeboxUI', 'VideoFit', JukeboxFit);
      F.WriteInteger('JukeboxUI', 'LyricPosition', JukeboxLyricPos);
      F.WriteInteger('JukeboxUI', 'Shade', JukeboxShade);
      F.WriteInteger('JukeboxUI', 'SungColour', JukeboxColSung);
      F.WriteInteger('JukeboxUI', 'TodoColour', JukeboxColTodo);
      F.WriteInteger('JukeboxUI', 'NextColour', JukeboxColNext);
      F.WriteBool('JukeboxUI', 'Shuffle', JukeboxStartShuffle);
      F.WriteBool('JukeboxUI', 'Lyrics', JukeboxStartLyrics);
      F.WriteBool('JukeboxUI', 'Repeat', JukeboxStartRepeat);
      F.UpdateFile;
    finally
      F.Free;
    end;
  except
    on E: Exception do
      Log.LogWarn('Could not save jukebox settings: ' + E.Message, 'JukeboxSaveSettings');
  end;
end;

function JTime(T: real): UTF8String;
var
  Secs: integer;
begin
  if (T < 0) then
    T := 0;
  Secs := Round(T);
  Result := Format('%d:%.2d', [Secs div 60, Secs mod 60]);
end;

// small round icon button; returns its rect
function JRoundButton(CX, CY, R: single; const Bg: TMColor): TMRect;
begin
  MFillCircle(CX, CY, R, Bg, 1);
  Result := MRect(CX - R, CY - R, R * 2, R * 2);
end;

procedure JCover(Tex: TTexture; X, Y, Size, Radius: single; const Bg: TMColor);
begin
  if (Tex <> nil) and not Tex.IsEmpty then
    MDrawTex(Tex, X, Y, Size, Size, 1)
  else
  begin
    MFillRect(X, Y, Size, Size, mcSurface2, 1);
    MIconNote(X + Size / 2, Y + Size / 2, Size * 0.4, mcBorder, 1);
  end;
  MCornerMask(X, Y, Size, Size, Radius, Bg);
end;

function JSongCover(ID: integer): TTexture;
begin
  Result := nil;
  if (ID >= 0) and (ID <= High(CatSongs.Song)) then
    Result := CatSongs.Song[ID].CoverTex;
end;

function TScreenJukebox.BarShown: boolean;
begin
  Result := Paused or (SDL_GetTicks() - LastSongMenuTick < JB_SHOW_MS);
end;

procedure TScreenJukebox.ShowBar;
begin
  LastSongMenuTick := SDL_GetTicks();
  SongMenuVisible := true;
end;

procedure TScreenJukebox.SyncCurrentIndex;
var
  I: integer;
begin
  for I := 0 to High(JukeboxVisibleSongs) do
    if (JukeboxVisibleSongs[I] = CurrentSongID) then
    begin
      CurrentSongList := I;
      Exit;
    end;
end;

procedure TScreenJukebox.SetSort(Order: integer);
begin
  LastTick := SDL_GetTicks();
  Button[JukeboxRandomSongList].SetSelect(false);
  Button[JukeboxSongListOrder].SetSelect(true);
  OrderType := Order;
  OrderMode := true;
  RandomMode := false;
  SongListSort(OrderType);
  SyncCurrentIndex;
end;

procedure TScreenJukebox.ToggleSearch;
begin
  LastTick := SDL_GetTicks();
  FindSongList := not FindSongList;
  if (Filter = '') and FindSongList then
    Button[JukeboxFindSong].Text[0].Text := '';
  Button[JukeboxFindSong].SetSelect(FindSongList);
  SetTextInput(FindSongList);
  if FindSongList then
    FilterSongList(Filter)
  else
  begin
    Filter := '';
    Button[JukeboxFindSong].Text[0].Text := '';
    FilterSongList('');
  end;
end;

procedure TScreenJukebox.OpenDisplay;
begin
  SongListVisible := false;
  FindSongList := false;
  StopTextInput;
  FDisplayVisible := true;
  FDisplayRow := 0;
  FDisplayBtn := 1;
end;

procedure TScreenJukebox.ChangeDisplayValue(Row, Delta: integer);
var
  V: integer;
begin
  case Row of
    0: JukeboxFit := (JukeboxFit + Delta + 3) mod 3;
    1:
      begin
        // 0 = off, 1 bottom, 2 middle, 3 top
        if ShowLyrics then
          V := JukeboxLyricPos
        else
          V := 0;
        V := JClamp(V + Delta, 0, 3);
        ShowLyrics := (V <> 0);
        if (V <> 0) then
          JukeboxLyricPos := V;
      end;
    2: JukeboxShade := JClamp(JukeboxShade + Delta, 0, 10);
    3: JukeboxColSung := (JukeboxColSung + Delta + 5) mod 5;
    4: JukeboxColTodo := (JukeboxColTodo + Delta + 5) mod 5;
    5: JukeboxColNext := (JukeboxColNext + Delta + 5) mod 5;
    6: FDisplayBtn := 1 - FDisplayBtn;
  end;
end;

// codes: Row * 100 + value; 200 = shade slider (value from X);
// 600 reset, 601 save, 700 close
procedure TScreenJukebox.DisplayClick(Code: integer; VX: single);
var
  Row, Value, I: integer;
begin
  Row := Code div 100;
  Value := Code mod 100;
  case Row of
    0: JukeboxFit := Value;
    1:
      begin
        ShowLyrics := (Value <> 0);
        if (Value <> 0) then
          JukeboxLyricPos := Value;
      end;
    2:
      begin
        for I := 0 to High(FDispCodes) do
          if (FDispCodes[I] = 200) then
            JukeboxShade := JClamp(Round((VX - FDispRects[I].X) / FDispRects[I].W * 10), 0, 10);
      end;
    3: JukeboxColSung := Value;
    4: JukeboxColTodo := Value;
    5: JukeboxColNext := Value;
    6:
      begin
        if (Value = 0) then
        begin
          JukeboxFit := 0;
          JukeboxLyricPos := 1;
          JukeboxShade := 6;
          JukeboxColSung := 0;
          JukeboxColTodo := 0;
          JukeboxColNext := 0;
          ShowLyrics := true;
        end
        else
        begin
          JukeboxSaveSettings;
          FDisplaySaved := SDL_GetTicks();
        end;
      end;
    7: FDisplayVisible := false;
  end;
  if (Row <= 6) then
    FDisplayRow := Row;
end;

function TScreenJukebox.ParseDisplayInput(PressedKey: cardinal): boolean;
begin
  Result := true;
  case PressedKey of
    SDLK_ESCAPE, SDLK_BACKSPACE, SDLK_O:
      FDisplayVisible := false;
    SDLK_UP:
      FDisplayRow := JClamp(FDisplayRow - 1, 0, 6);
    SDLK_DOWN:
      FDisplayRow := JClamp(FDisplayRow + 1, 0, 6);
    SDLK_LEFT:
      ChangeDisplayValue(FDisplayRow, -1);
    SDLK_RIGHT:
      ChangeDisplayValue(FDisplayRow, 1);
    SDLK_RETURN:
      if (FDisplayRow = 6) then
        DisplayClick(600 + FDisplayBtn, 0)
      else
        FDisplayRow := 6;
  end;
end;

procedure TScreenJukebox.AddDispRect(const R: TMRect; Code: integer);
begin
  SetLength(FDispRects, Length(FDispRects) + 1);
  SetLength(FDispCodes, Length(FDispCodes) + 1);
  FDispRects[High(FDispRects)] := R;
  FDispCodes[High(FDispCodes)] := Code;
end;

function TScreenJukebox.ParseMouseModern(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  VX, VY, Fr: single;
  I: integer;
  WasShown: boolean;
begin
  Result := true;
  MWindowToVirtual(X, Y, VX, VY);

  // mouse moved (or a button released): just bring the bar up
  if not BtnDown then
  begin
    if not SongListVisible and not FDisplayVisible then
      ShowBar;
    Exit;
  end;

  { display card }
  if FDisplayVisible then
  begin
    if (MouseButton = SDL_BUTTON_RIGHT) then
    begin
      FDisplayVisible := false;
      Exit;
    end;
    if (MouseButton <> SDL_BUTTON_LEFT) then
      Exit;
    for I := 0 to High(FDispRects) do
      if MHit(VX, VY, FDispRects[I]) then
      begin
        DisplayClick(FDispCodes[I], VX);
        Exit;
      end;
    if not MHit(VX, VY, FDisplayCard) then
      FDisplayVisible := false;
    Exit;
  end;

  { up next panel }
  if SongListVisible then
  begin
    LastTick := SDL_GetTicks();
    case MouseButton of
      SDL_BUTTON_WHEELDOWN:
        begin
          for I := 1 to 3 do
            ParseInput(SDLK_DOWN, 0, true);
          Exit;
        end;
      SDL_BUTTON_WHEELUP:
        begin
          for I := 1 to 3 do
            ParseInput(SDLK_UP, 0, true);
          Exit;
        end;
      SDL_BUTTON_RIGHT:
        begin
          SongListVisible := false;
          Exit;
        end;
    end;
    if (MouseButton <> SDL_BUTTON_LEFT) then
      Exit;

    // click on the video closes the list
    if (VX < MUI_W - JB_PANEL_W) then
    begin
      SongListVisible := false;
      Exit;
    end;

    if MHit(VX, VY, FSearchRect) then
    begin
      ToggleSearch;
      Exit;
    end;
    if MHit(VX, VY, FChipRects[0]) then
    begin
      SetSort(1);
      Exit;
    end;
    if MHit(VX, VY, FChipRects[1]) then
    begin
      SetSort(2);
      Exit;
    end;
    if MHit(VX, VY, FChipRects[2]) then
    begin
      RandomList();
      Exit;
    end;

    // click a song to select it, click it again to play it
    for I := 0 to High(FPanelRows) do
      if MHit(VX, VY, FPanelRows[I]) then
      begin
        if (FPanelRowIdx[I] = ActualInteraction) then
          Result := ParseInput(SDLK_RETURN, 0, true)
        else
          ActualInteraction := FPanelRowIdx[I];
        Exit;
      end;
    Exit;
  end;

  { player bar }
  if (MouseButton = SDL_BUTTON_RIGHT) then
  begin
    ScreenPopupCheck.ShowPopup('MSG_END_JUKEBOX', OnEscapeJukebox, nil, true);
    Exit;
  end;
  if (MouseButton <> SDL_BUTTON_LEFT) then
    Exit;

  WasShown := BarShown;
  ShowBar;
  // the first click only reveals the bar
  if not WasShown then
    Exit;

  if MHit(VX, VY, FBarRects[0]) then
    Result := ParseInput(SDLK_LEFT, 0, true)
  else if MHit(VX, VY, FBarRects[1]) then
    Pause
  else if MHit(VX, VY, FBarRects[2]) then
    Result := ParseInput(SDLK_RIGHT, 0, true)
  else if MHit(VX, VY, FBarRects[3]) then
  begin
    Fr := (VX - FBarRects[3].X) / FBarRects[3].W;
    if (Fr < 0) then
      Fr := 0;
    if (Fr > 1) then
      Fr := 1;
    ChangeTime(Fr * LyricsState.TotalTime);
  end
  else if MHit(VX, VY, FBarRects[4]) then
    RandomList()
  else if MHit(VX, VY, FBarRects[5]) then
    RepeatSongList := not RepeatSongList
  else if MHit(VX, VY, FBarRects[6]) then
    ShowLyrics := not ShowLyrics
  else if MHit(VX, VY, FBarRects[7]) then
  begin
    SongListVisible := true;
    ActualInteraction := CurrentSongList;
  end
  else if MHit(VX, VY, FBarRects[8]) then
    OpenDisplay;
end;

{ --- drawing --- }

procedure TScreenJukebox.DrawModernLyrics;
var
  CurY, NextY, Sh: single;
  Sung, Todo, Nxt: TMColor;
begin
  if not ShowLyrics or SongListVisible then
    Exit;
  // as before: start showing the lyrics 3 seconds before the first line
  if not (LyricsStart or (LyricsState.GetCurrentTime() * 1000 >= LyricsState.StartTime - 3000)) then
    Exit;
  LyricsStart := true;

  Sh := JukeboxShade / 10;
  case JukeboxLyricPos of
    2:
      begin
        CurY := 318;
        NextY := 374;
        MFillGradientV(0, 220, MUI_W, 100, mcBg, 0, Sh);
        MFillGradientV(0, 320, MUI_W, 120, mcBg, Sh, 0);
      end;
    3:
      begin
        CurY := 96;
        NextY := 152;
        MFillGradientV(0, 0, MUI_W, 240, mcBg, Sh, 0);
      end;
  else
    begin
      CurY := 500;
      NextY := 556;
      MFillGradientV(0, 380, MUI_W, MUI_H - 380, mcBg, 0, Sh);
    end;
  end;

  Sung := MColor(JSungCols[JukeboxColSung]);
  Todo := MColor(JTodoCols[JukeboxColTodo]);
  Nxt := MColor(JNextCols[JukeboxColNext]);
  ModernDrawLyricLine(Lyrics.GetUpperLine(), MUI_W / 2, CurY, 40, LyricsState.MidBeat, true, Sung, Todo, Nxt);
  ModernDrawLyricLine(Lyrics.GetLowerLine(), MUI_W / 2, NextY, 24, LyricsState.MidBeat, false, Sung, Todo, Nxt);
end;

procedure TScreenJukebox.DrawModernBar;
var
  R: TMRect;
  X, Y, W, CX, CY, PX, PW, Fr, CurT, TotT: single;
  NextIdx, I: integer;
  S: UTF8String;
  IC: TMColor;
begin
  MFillGradientV(0, 470, MUI_W, MUI_H - 470, mcBg, 0, 0.85);

  { up next chip, top right }
  NextIdx := CurrentSongList + 1;
  if (NextIdx > High(JukeboxVisibleSongs)) and RepeatSongList then
    NextIdx := 0;
  if (NextIdx >= 0) and (NextIdx <= High(JukeboxVisibleSongs)) and (NextIdx <> CurrentSongList) then
  begin
    S := CatSongs.Song[JukeboxVisibleSongs[NextIdx]].Title + '  -  ' + CatSongs.Song[JukeboxVisibleSongs[NextIdx]].Artist;
    W := MTextW(S, 15, true) + 76;
    if (W > 560) then
      W := 560;
    X := MUI_W - JB_PAD - W;
    Y := 26;
    MFillRound(X, Y, W, 50, 25, mcSurface, 1);
    MStrokeRound(X, Y, W, 50, 25, 1, mcBorder, 1);
    MFillCircle(X + 25, Y + 25, 18, mcSurface2, 1);
    MIconNote(X + 25, Y + 25, 16, mcMuted, 1);
    MText(X + 52, Y + 8, 'Up next', 12, false, mcMuted, 1);
    MText(X + 52, Y + 24, S, 15, true, mcText, 1, mtaLeft, W - 70);
  end;

  { the bar }
  R := MRect(JB_PAD, MUI_H - 28 - JB_BAR_H, MUI_W - 2 * JB_PAD, JB_BAR_H);
  MFillRound(R.X, R.Y, R.W, R.H, 28, mcSurface, 1);
  MStrokeRound(R.X, R.Y, R.W, R.H, 28, 1, mcBorder, 1);

  // cover, title, artist
  JCover(Statics[StaticCover].Texture, R.X + 14, R.Y + 14, 68, 16, mcSurface);
  MText(R.X + 100, R.Y + 24, CurrentSong.Title, 20, true, mcText, 1, mtaLeft, 250);
  MText(R.X + 100, R.Y + 52, CurrentSong.Artist, 15, false, mcMuted, 1, mtaLeft, 250);

  // previous, play/pause, next
  CY := R.Y + R.H / 2;
  CX := R.X + 394;
  FBarRects[0] := JRoundButton(CX, CY, 22, mcSurface2);
  Renderer.DrawTriangle(CX + 6, CY - 8, CX - 5, CY, CX + 6, CY + 8, 0, mcText.R, mcText.G, mcText.B, 1);
  MFillRect(CX - 8, CY - 8, 3, 16, mcText, 1);

  CX := CX + 58;
  FBarRects[1] := JRoundButton(CX, CY, 29, mcAccent);
  if Paused then
    MIconPlay(CX + 2, CY, 20, mcOnAccent, 1)
  else
  begin
    MFillRound(CX - 8, CY - 10, 5, 20, 2, mcOnAccent, 1);
    MFillRound(CX + 3, CY - 10, 5, 20, 2, mcOnAccent, 1);
  end;

  CX := CX + 58;
  FBarRects[2] := JRoundButton(CX, CY, 22, mcSurface2);
  Renderer.DrawTriangle(CX - 6, CY - 8, CX + 5, CY, CX - 6, CY + 8, 0, mcText.R, mcText.G, mcText.B, 1);
  MFillRect(CX + 5, CY - 8, 3, 16, mcText, 1);

  // progress
  CurT := LyricsState.GetCurrentTime();
  TotT := LyricsState.TotalTime;
  PX := CX + 22 + 66;
  PW := (R.X + R.W - 22 - 5 * 44 - 4 * 8) - 66 - PX;
  if (TotT > 0) then
    Fr := CurT / TotT
  else
    Fr := 0;
  if (Fr < 0) then
    Fr := 0;
  if (Fr > 1) then
    Fr := 1;
  MText(PX - 12, CY - 9, JTime(CurT), 14, false, mcMuted, 1, mtaRight);
  MFillRound(PX, CY - 3, PW, 6, 3, mcBorder, 1);
  if (PW * Fr > 1) then
    MFillRound(PX, CY - 3, PW * Fr, 6, 3, mcAccent, 1);
  MFillCircle(PX + PW * Fr, CY, 8, mcText, 1);
  MText(PX + PW + 12, CY - 9, '-' + JTime(TotT - CurT), 14, false, mcMuted, 1);
  FBarRects[3] := MRect(PX, CY - 18, PW, 36);

  // shuffle, repeat, lyrics, up next list, display
  CX := R.X + R.W - 22 - 5 * 44 - 4 * 8 + 22;
  for I := 4 to 8 do
  begin
    FBarRects[I] := JRoundButton(CX, CY, 22, mcSurface2);
    case I of
      4:
        begin
          if RandomMode then IC := mcAccent else IC := mcMuted;
          MLine(CX - 8, CY - 6, CX + 8, CY + 6, 2.2, IC, 1);
          MLine(CX - 8, CY + 6, CX + 8, CY - 6, 2.2, IC, 1);
          MLine(CX + 8, CY - 6, CX + 3, CY - 6, 2.2, IC, 1);
          MLine(CX + 8, CY + 6, CX + 3, CY + 6, 2.2, IC, 1);
        end;
      5:
        begin
          if RepeatSongList then IC := mcAccent else IC := mcMuted;
          MStrokeRound(CX - 9, CY - 6, 18, 12, 5, 2, IC, 1);
          Renderer.DrawTriangle(CX + 1, CY - 10, CX + 6, CY - 6, CX + 1, CY - 2, 0, IC.R, IC.G, IC.B, 1);
        end;
      6:
        begin
          if ShowLyrics then IC := mcAccent else IC := mcMuted;
          MFillRect(CX - 9, CY - 7, 18, 2.5, IC, 1);
          MFillRect(CX - 9, CY - 1, 18, 2.5, IC, 1);
          MFillRect(CX - 9, CY + 5, 11, 2.5, IC, 1);
        end;
      7:
        begin
          MFillRect(CX - 9, CY - 7, 13, 2.5, mcText, 1);
          MFillRect(CX - 9, CY - 1, 13, 2.5, mcText, 1);
          MFillRect(CX - 9, CY + 5, 8, 2.5, mcText, 1);
          MFillCircle(CX + 6, CY + 6, 3, mcText, 1);
          MFillRect(CX + 8, CY - 6, 2, 12, mcText, 1);
        end;
      8:
        begin
          MFillRect(CX - 9, CY - 5, 18, 2, mcText, 1);
          MFillCircle(CX - 3, CY - 4, 3.5, mcText, 1);
          MFillRect(CX - 9, CY + 4, 18, 2, mcText, 1);
          MFillCircle(CX + 4, CY + 5, 3.5, mcText, 1);
        end;
    end;
    CX := CX + 52;
  end;
end;

procedure TScreenJukebox.DrawModernPanel;
var
  PX, X, Y, W, TW, CurT: single;
  I, Idx, N, SongID, Sel: integer;
  R: TMRect;
  RowBg: TMColor;
  Playing, IsSel: boolean;
  Lbl, S: UTF8String;
  Labels: array[0..2] of UTF8String;
begin
  // video stays visible, dimmed
  MFillRect(0, 0, MUI_W, MUI_H, mcBg, 0.45);

  { small now-playing pill, bottom left }
  S := CurrentSong.Artist + '  -  ' + JTime(LyricsState.GetCurrentTime()) + ' / ' + JTime(LyricsState.TotalTime);
  W := MTextW(CurrentSong.Title, 16, true);
  TW := MTextW(S, 13, false);
  if (TW > W) then
    W := TW;
  W := W + 90;
  if (W > MUI_W - JB_PANEL_W - 2 * JB_PAD) then
    W := MUI_W - JB_PANEL_W - 2 * JB_PAD;
  X := JB_PAD;
  Y := MUI_H - 28 - 60;
  MFillRound(X, Y, W, 60, 30, mcSurface, 1);
  MStrokeRound(X, Y, W, 60, 30, 1, mcBorder, 1);
  JCover(Statics[StaticCover].Texture, X + 10, Y + 10, 40, 20, mcSurface);
  MText(X + 62, Y + 11, CurrentSong.Title, 16, true, mcText, 1, mtaLeft, W - 80);
  MText(X + 62, Y + 33, S, 13, false, mcMuted, 1, mtaLeft, W - 80);

  { panel }
  PX := MUI_W - JB_PANEL_W;
  MFillRect(PX, 0, JB_PANEL_W, MUI_H, mcBg, 1);
  MFillRect(PX, 0, 1, MUI_H, mcBorder, 1);

  MText(PX + 28, 30, 'Up next', 26, true, mcText, 1);
  N := Length(JukeboxVisibleSongs);
  if (N > 0) then
    Lbl := IntToStr(ActualInteraction + 1) + ' of ' + IntToStr(N)
  else
    Lbl := 'No songs';
  MText(PX + JB_PANEL_W - 28, 40, Lbl, 14, false, mcMuted, 1, mtaRight);

  // search
  FSearchRect := MRect(PX + 28, 80, JB_PANEL_W - 56, 46);
  R := FSearchRect;
  MFillRound(R.X, R.Y, R.W, R.H, 23, mcSurface, 1);
  if FindSongList then
    MStrokeRound(R.X, R.Y, R.W, R.H, 23, 2, mcAccent, 1)
  else
    MStrokeRound(R.X, R.Y, R.W, R.H, 23, 1, mcBorder, 1);
  MIconSearch(R.X + 26, R.Y + 23, 16, mcMuted, 1);
  if (Filter = '') and not FindSongList then
    MText(R.X + 48, R.Y + 14, 'Find a song in this list  (J)', 15, false, mcMuted, 1, mtaLeft, R.W - 64)
  else
  begin
    MText(R.X + 48, R.Y + 13, Filter, 16, false, mcText, 1, mtaLeft, R.W - 64);
    if FindSongList and ((SDL_GetTicks() div 500) mod 2 = 0) then
    begin
      TW := MTextW(Filter, 16, false);
      if (TW > R.W - 64) then
        TW := R.W - 64;
      MFillRect(R.X + 50 + TW, R.Y + 12, 2, 22, mcAccent, 1);
    end;
  end;

  // sort chips
  Labels[0] := 'Artist';
  Labels[1] := 'Title';
  Labels[2] := 'Shuffle';
  if RandomMode then
    Sel := 2
  else if OrderMode and (OrderType = 1) then
    Sel := 0
  else if OrderMode and (OrderType = 2) then
    Sel := 1
  else
    Sel := -1;
  X := PX + 28;
  for I := 0 to 2 do
  begin
    W := MTextW(Labels[I], 14, I = Sel) + 32;
    FChipRects[I] := MRect(X, 140, W, 36);
    if (I = Sel) then
    begin
      MFillRound(X, 140, W, 36, 18, mcText, 1);
      MText(X + 16, 150, Labels[I], 14, true, mcBg, 1);
    end
    else
    begin
      MFillRound(X, 140, W, 36, 18, mcSurface, 1);
      MStrokeRound(X, 140, W, 36, 18, 1, mcBorder, 1);
      MText(X + 16, 150, Labels[I], 14, false, mcMuted, 1);
    end;
    X := X + W + 8;
  end;

  // song rows
  if (ActualInteraction < FPanelTop) then
    FPanelTop := ActualInteraction;
  if (ActualInteraction >= FPanelTop + JB_ROWS) then
    FPanelTop := ActualInteraction - JB_ROWS + 1;
  if (FPanelTop > N - JB_ROWS) then
    FPanelTop := N - JB_ROWS;
  if (FPanelTop < 0) then
    FPanelTop := 0;

  SetLength(FPanelRows, 0);
  SetLength(FPanelRowIdx, 0);
  if (N = 0) then
    MText(PX + JB_PANEL_W / 2, 300, 'No songs match', 16, false, mcMuted, 1, mtaCenter);

  Y := 192;
  for I := 0 to JB_ROWS - 1 do
  begin
    Idx := FPanelTop + I;
    if (Idx >= N) then
      Break;
    SongID := JukeboxVisibleSongs[Idx];
    Playing := (SongID = CurrentSongID);
    IsSel := (Idx = ActualInteraction);
    R := MRect(PX + 18, Y, JB_PANEL_W - 36, JB_ROW_H);

    SetLength(FPanelRows, Length(FPanelRows) + 1);
    SetLength(FPanelRowIdx, Length(FPanelRowIdx) + 1);
    FPanelRows[High(FPanelRows)] := R;
    FPanelRowIdx[High(FPanelRowIdx)] := Idx;

    if IsSel then
      RowBg := mcSurface2
    else if Playing then
      RowBg := mcSurface
    else
      RowBg := mcBg;
    if IsSel or Playing then
      MFillRound(R.X, R.Y, R.W, R.H, 14, RowBg, 1);
    if IsSel then
      MStrokeRound(R.X, R.Y, R.W, R.H, 14, 2, mcText, 1);

    JCover(JSongCover(SongID), R.X + 10, R.Y + 7, 42, 10, RowBg);
    if Playing then
    begin
      // little level meter over the cover
      MFillRect(R.X + 10, R.Y + 7, 42, 42, mcBg, 0.55);
      MFillRect(R.X + 21, R.Y + 25, 4, 14, mcAccent, 1);
      MFillRect(R.X + 29, R.Y + 18, 4, 21, mcAccent, 1);
      MFillRect(R.X + 37, R.Y + 28, 4, 11, mcAccent, 1);
    end;

    if Playing then
      MText(R.X + 66, R.Y + 9, CatSongs.Song[SongID].Title, 15, true, mcAccent, 1, mtaLeft, R.W - 80)
    else
      MText(R.X + 66, R.Y + 9, CatSongs.Song[SongID].Title, 15, true, mcText, 1, mtaLeft, R.W - 80);
    MText(R.X + 66, R.Y + 30, CatSongs.Song[SongID].Artist, 13, false, mcMuted, 1, mtaLeft, R.W - 80);

    Y := Y + JB_ROW_H + 4;
  end;

  // footer
  X := PX + 28;
  X := X + MKeyHint(X, 686, 'Enter', 'play') + 16;
  X := X + MKeyHint(X, 686, 'Del', 'remove') + 16;
  MKeyHint(X, 686, 'Esc', 'close');
end;

procedure TScreenJukebox.DrawModernDisplay;
var
  C: TMRect;
  X, Y, W, RX, BW, TW, SX: single;
  J, Row, Cur: integer;
  Labels: array[0..3] of UTF8String;
  Cols: array[0..4] of cardinal;
  Sung, Todo, Nxt: TMColor;
  S1, S2: UTF8String;

  // segmented control, right-aligned in the card; each segment is clickable
  procedure Segments(SegRow, Count, Selected: integer; SegY: single);
  var
    K: integer;
    SW, SXX, Total: single;
  begin
    Total := 8;
    for K := 0 to Count - 1 do
      Total := Total + MTextW(Labels[K], 15, K = Selected) + 40;
    SXX := C.X + C.W - 34 - Total;
    MFillRound(SXX, SegY, Total, 46, 23, mcBg, 1);
    if (FDisplayRow = SegRow) then
      MStrokeRound(SXX - 5, SegY - 5, Total + 10, 56, 28, 3, mcText, 1);
    SXX := SXX + 4;
    for K := 0 to Count - 1 do
    begin
      SW := MTextW(Labels[K], 15, K = Selected) + 40;
      if (K = Selected) then
      begin
        MFillRound(SXX, SegY + 4, SW, 38, 19, mcText, 1);
        MText(SXX + 20, SegY + 14, Labels[K], 15, true, mcBg, 1);
      end
      else
        MText(SXX + 20, SegY + 14, Labels[K], 15, false, mcMuted, 1);
      AddDispRect(MRect(SXX, SegY + 4, SW, 38), SegRow * 100 + K);
      SXX := SXX + SW;
    end;
  end;

begin
  SetLength(FDispRects, 0);
  SetLength(FDispCodes, 0);

  MFillRect(0, 0, MUI_W, MUI_H, mcBg, 0.6);
  C := MRect((MUI_W - 700) / 2, 60, 700, 600);
  FDisplayCard := C;
  MFillRound(C.X, C.Y, C.W, C.H, 28, mcSurface, 1);
  MStrokeRound(C.X, C.Y, C.W, C.H, 28, 1, mcBorder, 1);

  MText(C.X + 34, C.Y + 30, 'Display', 26, true, mcText, 1);
  // close
  MFillCircle(C.X + C.W - 54, C.Y + 46, 20, mcSurface2, 1);
  MLine(C.X + C.W - 61, C.Y + 39, C.X + C.W - 47, C.Y + 53, 2.2, mcText, 1);
  MLine(C.X + C.W - 47, C.Y + 39, C.X + C.W - 61, C.Y + 53, 2.2, mcText, 1);
  AddDispRect(MRect(C.X + C.W - 74, C.Y + 26, 40, 40), 700);

  { video fit }
  Y := C.Y + 92;
  MText(C.X + 34, Y + 14, 'Video', 17, false, mcText, 1);
  Labels[0] := 'Fill';
  Labels[1] := 'Fit';
  Labels[2] := 'Halfway';
  Segments(0, 3, JukeboxFit, Y);

  { lyrics position }
  Y := Y + 62;
  MText(C.X + 34, Y + 14, 'Lyrics', 17, false, mcText, 1);
  Labels[0] := 'Off';
  Labels[1] := 'Bottom';
  Labels[2] := 'Middle';
  Labels[3] := 'Top';
  if ShowLyrics then
    Cur := JukeboxLyricPos
  else
    Cur := 0;
  Segments(1, 4, Cur, Y);

  { shade }
  Y := Y + 62;
  MText(C.X + 34, Y + 14, 'Shade behind lyrics', 17, false, mcText, 1);
  W := 300;
  RX := C.X + C.W - 34 - W;
  MFillRound(RX, Y + 20, W, 6, 3, mcBorder, 1);
  if (JukeboxShade > 0) then
    MFillRound(RX, Y + 20, W * JukeboxShade / 10, 6, 3, mcAccent, 1);
  MFillCircle(RX + W * JukeboxShade / 10, Y + 23, 10, mcText, 1);
  if (FDisplayRow = 2) then
    MStrokeRound(RX - 18, Y + 3, W + 36, 40, 20, 3, mcText, 1);
  AddDispRect(MRect(RX - 10, Y + 3, W + 20, 40), 200);

  { colours }
  Y := Y + 62;
  MText(C.X + 34, Y, 'Lyric colours', 17, false, mcText, 1);
  Y := Y + 30;
  BW := (C.W - 68 - 2 * 14) / 3;
  for Row := 3 to 5 do
  begin
    X := C.X + 34 + (Row - 3) * (BW + 14);
    MFillRound(X, Y, BW, 84, 18, mcBg, 1);
    if (FDisplayRow = Row) then
      MStrokeRound(X - 4, Y - 4, BW + 8, 92, 21, 3, mcText, 1);
    case Row of
      3: begin S1 := 'Sung'; Cur := JukeboxColSung; for J := 0 to 4 do Cols[J] := JSungCols[J]; end;
      4: begin S1 := 'Still to sing'; Cur := JukeboxColTodo; for J := 0 to 4 do Cols[J] := JTodoCols[J]; end;
    else
      begin S1 := 'Next line'; Cur := JukeboxColNext; for J := 0 to 4 do Cols[J] := JNextCols[J]; end;
    end;
    MText(X + 16, Y + 14, S1, 13, false, mcMuted, 1);
    for J := 0 to 4 do
    begin
      SX := X + 16 + J * 34;
      if (J = Cur) then
      begin
        MFillCircle(SX + 13, Y + 55, 16, mcText, 1);
        MFillCircle(SX + 13, Y + 55, 13.5, mcBg, 1);
      end;
      MFillCircle(SX + 13, Y + 55, 11, MColor(Cols[J]), 1);
      AddDispRect(MRect(SX, Y + 40, 30, 30), Row * 100 + J);
    end;
  end;

  { preview }
  Y := Y + 84 + 20;
  MFillRound(C.X + 34, Y, C.W - 68, 84, 18, mcBg, 1);
  Sung := MColor(JSungCols[JukeboxColSung]);
  Todo := MColor(JTodoCols[JukeboxColTodo]);
  Nxt := MColor(JNextCols[JukeboxColNext]);
  S1 := 'This is how ';
  S2 := 'the lyrics will look';
  TW := MTextW(S1 + S2, 26, true);
  X := C.X + C.W / 2 - TW / 2;
  MText(X, Y + 14, S1, 26, true, Sung, 1);
  MText(X + MTextW(S1, 26, true), Y + 14, S2, 26, true, Todo, 1);
  MText(C.X + C.W / 2, Y + 52, 'with the next line underneath', 17, false, Nxt, 1, mtaCenter);

  { buttons }
  Y := C.Y + C.H - 30 - 50;
  S1 := 'Save for every song';
  BW := MTextW(S1, 16, true) + 56;
  X := C.X + C.W - 34 - BW;
  MFillRound(X, Y, BW, 50, 25, mcAccent, 1);
  MText(X + 28, Y + 15, S1, 16, true, mcOnAccent, 1);
  AddDispRect(MRect(X, Y, BW, 50), 601);
  if (FDisplayRow = 6) and (FDisplayBtn = 1) then
    MStrokeRound(X - 5, Y - 5, BW + 10, 60, 30, 3, mcText, 1);

  W := MTextW('Reset', 16, false) + 48;
  X := X - 12 - W;
  MFillRound(X, Y, W, 50, 25, mcSurface2, 1);
  MText(X + 24, Y + 15, 'Reset', 16, false, mcText, 1);
  AddDispRect(MRect(X, Y, W, 50), 600);
  if (FDisplayRow = 6) and (FDisplayBtn = 0) then
    MStrokeRound(X - 5, Y - 5, W + 10, 60, 30, 3, mcText, 1);

  if (FDisplaySaved > 0) and (SDL_GetTicks() - FDisplaySaved < 2000) then
    MText(C.X + 34, Y + 15, 'Saved', 16, true, mcAccent, 1);
end;

procedure TScreenJukebox.DrawModern;
var
  Shown: boolean;
begin
  if (CurrentSong = nil) then
    Exit;
  Shown := BarShown and not SongListVisible and not FDisplayVisible;
  SongMenuVisible := Shown;

  MBegin;
  DrawModernLyrics;
  if Shown then
    DrawModernBar;
  if SongListVisible then
    DrawModernPanel;
  if FDisplayVisible then
    DrawModernDisplay;
  MEnd;
end;

end.
