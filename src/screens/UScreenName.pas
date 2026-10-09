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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenName.pas $
 * $Id: UScreenName.pas 1939 2009-11-09 00:27:55Z s_alexander $
 *}

unit UScreenName;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UAvatars,
  UDisplay,
  UFiles,
  UIni,
  UMenu,
  UModernUI,
  UMusic,
  UNote,
  URenderer,
  UScreenScore,
  UScreenSingController,
  UScreenTop5,
  UThemes,
  SysUtils,
  sdl2,
  md5;

type
  TScreenName = class(TMenu)
    private
      PlayersCount:  cardinal;
      PlayerAvatar:  cardinal;
      PlayerName:    cardinal;
      PlayerColor:   cardinal;
      PlayerSelect:  cardinal;
      PlayerSelectLevel: cardinal;

      CountIndex:   integer;
      PlayerIndex:  integer;
      ColorIndex:   integer;
      LevelIndex:   integer;

      PlayerAvatarIID: integer; // interaction ID

      AvatarCurrent: real;
      AvatarTarget:  integer;

      NumVisibleAvatars:      integer;
      DistanceVisibleAvatars: integer;

      isScrolling: boolean;   // true if avatar flow is about to move

      PlayerCurrent:       array [0..UIni.IMaxPlayerCount-1] of integer;
      PlayerCurrentText:   array [0..UIni.IMaxPlayerCount-1] of integer;
      PlayerCurrentAvatar: array [0..UIni.IMaxPlayerCount-1] of integer;

      PlayerNames:   array [0..UIni.IMaxPlayerCount-1] of UTF8String;
      PlayerAvatars: array [0..UIni.IMaxPlayerCount-1] of integer;
      PlayerLevel:   array [0..UIni.IMaxPlayerCount-1] of integer;

      APlayerColor: array of integer;

      PlayerAvatarButton: array of integer;
      PlayerAvatarButtonMD5: array of UTF8String;

      // ui-v2 (Midnight) player setup
      FRow: integer;   // 0 singers count, 1 singer cards, 2 avatar, 3 colour, 4 name
      FRingX, FRingY, FRingW, FRingH: single;
      FRingReady: boolean;
      FCountRects: array[0..4] of TMRect;
      FCardRects: array[0..UIni.IMaxPlayerCount-1] of TMRect;
      FBackRect, FContinueRect, FAvatarRect, FAvatarPrev, FAvatarNext, FNameRect: TMRect;
      FColorPill: TMRect;
      FColorRects: array[0..15] of TMRect;
      function CardSize: single;
      function AvatarTexture(P: integer): TTexture;
      procedure SetCount(Index: integer);
      procedure SelectPlayer(Index: integer);
      procedure StepAvatar(Delta: integer);
      function ColorUsedByOther(K: integer): boolean;
      procedure SetColor(K: integer);
      procedure StepColor(Delta: integer);
      procedure SetRow(Row: integer);
      procedure GoBack;
      procedure ContinueToSongs;
    public
      Goto_SingScreen: boolean; //If true then next Screen in SingScreen
      
      constructor Create; override;
      function ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;

      procedure OnShow; override;
      function Draw: boolean; override;

      procedure SetAvatarScroll;
      procedure SelectNext;
      procedure SelectPrev;

      procedure PlayerColorButton(K: integer);
      function NoRepeatColors(ColorP: integer; Interaction: integer; Pos: integer):integer;
      procedure RefreshPlayers();
      procedure RefreshProfile();
      procedure RefreshColor();

      procedure ChangeSelectPlayerPosition(Player: integer);

      procedure GenerateAvatars();
      procedure SetPlayerAvatar(Player: integer);
  end;

var
  Num: array[0..UIni.IMaxPlayerCount-1]of integer;

const
  ID='ID_010';   //for help system

implementation

uses

  UCommon,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UMain,
  UMenuButton,
  UPath,
  USkins,
  USongs,
  UTime,
  UUnicodeUtils,
  Math;

{ =====================================================================
  ui-v2: Midnight player setup
  Rows: 0 = number of singers, 1 = singer cards, 2 = avatar (arrows on
  the selected card), 3 = colour swatches, 4 = name.
  Difficulty is no longer shown; each singer keeps the saved value.
  Two singers can't share a colour.
  ===================================================================== }

const
  PN_PAD = 56;
  ROW_NAME = 4;

function PlayerMColor(ColorNum: integer): TMColor;
var
  C: TRGB;
begin
  C := GetPlayerColor(ColorNum);
  Result.R := C.R;
  Result.G := C.G;
  Result.B := C.B;
end;

function TScreenName.CardSize: single;
var
  N: integer;
begin
  N := UIni.IPlayersVals[CountIndex];
  Result := (MUI_W - 2 * PN_PAD - (N - 1) * 20) / N;
  if (Result > 200) then
    Result := 200;
end;

procedure TScreenName.SetCount(Index: integer);
begin
  if (Index < 0) or (Index > High(UIni.IPlayersVals)) then
    Exit;
  CountIndex := Index;
  RefreshPlayers;
end;

procedure TScreenName.SelectPlayer(Index: integer);
begin
  if (Index < 0) or (Index >= UIni.IPlayersVals[CountIndex]) then
    Exit;
  PlayerIndex := Index;
  RefreshProfile;
  AvatarTarget := PlayerAvatars[PlayerIndex];
  AvatarCurrent := AvatarTarget;
end;

procedure TScreenName.StepAvatar(Delta: integer);
var
  N: integer;
begin
  N := Length(AvatarsList);
  if (N <= 0) then
    Exit;
  PlayerAvatars[PlayerIndex] := (PlayerAvatars[PlayerIndex] + Delta + N) mod N;
  SetPlayerAvatar(PlayerIndex);
end;

function TScreenName.ColorUsedByOther(K: integer): boolean;
var
  J: integer;
begin
  Result := false;
  for J := 0 to UIni.IPlayersVals[CountIndex] - 1 do
    if (J <> PlayerIndex) and (Num[J] = K) then
    begin
      Result := true;
      Exit;
    end;
end;

procedure TScreenName.SetColor(K: integer);
begin
  if (K < 1) or (K > Length(IPlayerColorTranslated)) or ColorUsedByOther(K) then
    Exit;
  PlayerColorButton(K);
  SetPlayerAvatar(PlayerIndex);
end;

procedure TScreenName.StepColor(Delta: integer);
var
  K, N, Tries: integer;
begin
  N := Length(IPlayerColorTranslated);
  K := Num[PlayerIndex];
  for Tries := 1 to N do
  begin
    K := ((K - 1 + Delta + N) mod N) + 1;
    if not ColorUsedByOther(K) then
    begin
      SetColor(K);
      Exit;
    end;
  end;
end;

procedure TScreenName.SetRow(Row: integer);
begin
  if (Row < 0) then
    Row := 0;
  if (Row > ROW_NAME) then
    Row := ROW_NAME;
  FRow := Row;
  SetTextInput(FRow = ROW_NAME);
end;

procedure TScreenName.GoBack;
begin
  StopTextInput;
  Ini.SaveNames;
  AudioPlayback.PlaySound(SoundLib.Back);
  if GoTo_SingScreen then
    FadeTo(@ScreenSong)
  else
    FadeTo(@ScreenMain);
end;

procedure TScreenName.ContinueToSongs;
var
  I: integer;
  Col: TRGB;
begin
  StopTextInput;
  Ini.Players := CountIndex;
  PlayersPlay:= UIni.IPlayersVals[CountIndex];
  SetLength(Player, PlayersPlay);

  for I := 1 to PlayersPlay do
  begin
    // TODO: is it really necessary for this screen to duplicate all these Ini. arrays?
    Ini.Name[I-1] := PlayerNames[I-1];
    Ini.PlayerColor[I-1] := Num[I-1];
    Ini.SingColor[I-1] := Num[I-1];
    Ini.PlayerLevel[I-1] := PlayerLevel[I-1];
    // also set (some) of this info in the much easier to use Player variable
    Player[I-1].Name := PlayerNames[I-1];
    Player[I-1].Level := PlayerLevel[I-1];

    Ini.PlayerAvatar[I-1] := PlayerAvatarButtonMD5[PlayerAvatars[I-1]];

    if (PlayerAvatars[I-1] = 0) then
    begin
      AvatarPlayerTextures[I] := NoAvatartexture[I];

      Col := GetPlayerColor(Num[I-1]);

      AvatarPlayerTextures[I].ColR := Col.R;
      AvatarPlayerTextures[I].ColG := Col.G;
      AvatarPlayerTextures[I].ColB := Col.B;
    end
    else
    begin
      Button[PlayerAvatarButton[PlayerAvatars[I-1]]].Texture.Int := 1;
      AvatarPlayerTextures[I] := Button[PlayerAvatarButton[PlayerAvatars[I-1]]].Texture.Clone();
    end;

  end;

  Ini.SaveNumberOfPlayers;
  Ini.SaveNames;
  Ini.SavePlayerColors;
  Ini.SavePlayerAvatars;
  Ini.SavePlayerLevels;

  LoadPlayersColors;
  Theme.ThemeScoreLoad;

  // Reload ScreenSing and ScreenScore because of player colors
  // TODO: do this better  REALLY NECESSARY?
  ScreenScore.Free;
  ScreenSing.Free;

  ScreenScore := TScreenScore.Create;
  ScreenSing  := TScreenSingController.Create;

  AudioPlayback.PlaySound(SoundLib.Start);

  if GoTo_SingScreen then
  begin
    // if we've been in the player screen, we need to show the warning again
    ScreenSing.CheckPlayerConfigOnNextSong := true;
    FadeTo(@ScreenSing);
    GoTo_SingScreen := false;
  end
  else
  begin
    FadeTo(@ScreenSong);
    GoTo_SingScreen := false;
  end;
end;

function TScreenName.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
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
      if (FRow = 2) then StepAvatar(1);
    SDL_BUTTON_WHEELUP:
      if (FRow = 2) then StepAvatar(-1);
    SDL_BUTTON_LEFT:
      begin
        MWindowToVirtual(X, Y, VX, VY);

        if MHit(VX, VY, FBackRect) then
        begin
          GoBack;
          Exit;
        end;
        if MHit(VX, VY, FContinueRect) then
        begin
          ContinueToSongs;
          Exit;
        end;

        for I := 0 to High(UIni.IPlayersVals) do
          if MHit(VX, VY, FCountRects[I]) then
          begin
            SetCount(I);
            SetRow(0);
            Exit;
          end;

        // avatar arrows sit on the selected card, so test them first
        if MHit(VX, VY, FAvatarPrev) then
        begin
          StepAvatar(-1);
          SetRow(2);
          Exit;
        end;
        if MHit(VX, VY, FAvatarNext) then
        begin
          StepAvatar(1);
          SetRow(2);
          Exit;
        end;
        if MHit(VX, VY, FAvatarRect) then
        begin
          SetRow(2);
          Exit;
        end;

        for I := 0 to UIni.IPlayersVals[CountIndex] - 1 do
          if MHit(VX, VY, FCardRects[I]) then
          begin
            SelectPlayer(I);
            SetRow(1);
            Exit;
          end;

        for I := 0 to High(FColorRects) do
          if MHit(VX, VY, FColorRects[I]) then
          begin
            SetColor(I + 1);
            SetRow(3);
            Exit;
          end;

        if MHit(VX, VY, FColorPill) then
          SetRow(3)
        else if MHit(VX, VY, FNameRect) then
          SetRow(ROW_NAME);
      end;
  end;
end;

function TScreenName.ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean;
begin
  Result := inherited;
  // only suppress special keys for now
  case PressedKey of
    // Templates for Names Mod
    SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6, SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11, SDLK_F12:
     if (FRow = ROW_NAME) then
     begin
       SuppressKey := true;
     end
     else
     begin
       Result := false;
     end;
  end;
end;

function TScreenName.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
  var
    SDL_ModState: word;
    Len: integer;

  procedure HandleNameTemplate(const index: integer);
  var
    isAlternate: boolean;
  begin
    if (FRow <> ROW_NAME) then
      Exit;
    isAlternate := (SDL_ModState = KMOD_LSHIFT) or (SDL_ModState = KMOD_RSHIFT);
    isAlternate := isAlternate or (SDL_ModState = KMOD_LALT); // legacy key combination

    if isAlternate then
      Ini.NameTemplate[index] := PlayerNames[PlayerIndex]
    else
      PlayerNames[PlayerIndex] := Ini.NameTemplate[index];
  end;

begin
  Result := true;
  if not PressedDown then
    Exit;

  SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
  + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT);

  // typing a name
  if (FRow = ROW_NAME) and IsPrintableChar(CharCode) then
  begin
    PlayerNames[PlayerIndex] := PlayerNames[PlayerIndex] + UCS4ToUTF8String(CharCode);
    Exit;
  end;

  if (FRow <> ROW_NAME) and (PressedKey = SDLK_Q) then
  begin
    Result := false;
    Exit;
  end;

  case PressedKey of
    // Templates for Names Mod
    SDLK_F1: HandleNameTemplate(0);
    SDLK_F2: HandleNameTemplate(1);
    SDLK_F3: HandleNameTemplate(2);
    SDLK_F4: HandleNameTemplate(3);
    SDLK_F5: HandleNameTemplate(4);
    SDLK_F6: HandleNameTemplate(5);
    SDLK_F7: HandleNameTemplate(6);
    SDLK_F8: HandleNameTemplate(7);
    SDLK_F9: HandleNameTemplate(8);
    SDLK_F10: HandleNameTemplate(9);
    SDLK_F11: HandleNameTemplate(10);
    SDLK_F12: HandleNameTemplate(11);

    SDLK_BACKSPACE:
      begin
        if (FRow = ROW_NAME) then
        begin
          Len := LengthUTF8(PlayerNames[PlayerIndex]);
          if (Len > 0) then
            PlayerNames[PlayerIndex] := UTF8Copy(PlayerNames[PlayerIndex], 1, Len - 1);
        end
        else
          GoBack;
      end;

    SDLK_TAB:
      ScreenPopupHelp.ShowPopup();

    SDLK_ESCAPE:
      GoBack;

    SDLK_RETURN:
      ContinueToSongs;

    SDLK_DOWN:
      SetRow(FRow + 1);

    SDLK_UP:
      SetRow(FRow - 1);

    SDLK_RIGHT:
      case FRow of
        0: SetCount(CountIndex + 1);
        1: SelectPlayer(PlayerIndex + 1);
        2: StepAvatar(1);
        3: StepColor(1);
      end;

    SDLK_LEFT:
      case FRow of
        0: SetCount(CountIndex - 1);
        1: SelectPlayer(PlayerIndex - 1);
        2: StepAvatar(-1);
        3: StepColor(-1);
      end;
  end;
end;

procedure TScreenName.GenerateAvatars();
var
  I: integer;
  Avatar: TAvatar;
  AvatarFile: IPath;
  Hash: string;
begin

  SetLength(PlayerAvatarButton, Length(AvatarsList) + 1);
  SetLength(PlayerAvatarButtonMD5, Length(AvatarsList) + 1);

  // 1st no-avatar dummy
  for I := 1 to UIni.IMaxPlayerCount do
  begin
    NoAvatarTexture[I] := Renderer.GetTexture(Skin.GetTextureFileName('NoAvatar_P' + IntToStr(I)), TEXTURE_TYPE_TRANSPARENT, $FFFFFF);
  end;

  // create no-avatar
  PlayerAvatarButton[0] := AddButton(Theme.Name.PlayerAvatar);
  Button[PlayerAvatarButton[0]].Texture.Free;
  Button[PlayerAvatarButton[0]].Texture := NoAvatarTexture[1].Clone;
  Button[PlayerAvatarButton[0]].Selectable := false;
  Button[PlayerAvatarButton[0]].Selected := false;
  Button[PlayerAvatarButton[0]].Visible := false;

  // create avatars buttons
  for I := 1 to High(AvatarsList) do
  begin
    // create avatar
    PlayerAvatarButton[I] := AddButton(Theme.Name.PlayerAvatar);

    AvatarFile := AvatarsList[I];

    Hash := MD5Print(MD5File(AvatarFile.ToNative));
    PlayerAvatarButtonMD5[I] := UpperCase(Hash);

    // load avatar and cache its texture
    Avatar := Avatars.FindAvatar(AvatarFile);
    if (Avatar = nil) then
      Avatar := Avatars.AddAvatar(AvatarFile);

    if (Avatar <> nil) then
    begin
      Button[PlayerAvatarButton[I]].Texture.Free;
      Button[PlayerAvatarButton[I]].Texture := Avatar.GetTexture();
      Button[PlayerAvatarButton[I]].Selectable := false;
      Button[PlayerAvatarButton[I]].Selected := false;
      Button[PlayerAvatarButton[I]].Visible := false;
    end;

    Avatar.Free;
  end;

end;

procedure TScreenName.ChangeSelectPlayerPosition(Player: integer);
begin
  Button[PlayerSelect].X := Theme.Name.PlayerSelect[Player].X + Theme.Name.PlayerSelectCurrent.X;
end;

procedure TScreenName.RefreshPlayers();
var
  Count, I: integer;
  DesCol: TRGB;
begin

  Count := UIni.IPlayersVals[CountIndex];

  while (PlayerIndex > Count-1) do
    PlayerIndex := PlayerIndex - 1;

  // Player Colors
  for I := Count-1 downto 0 do
  begin
    if (Ini.PlayerColor[I] > 0) then
      Num[I] := NoRepeatColors(Ini.PlayerColor[I], I, 1)
    else
      Num[I] := NoRepeatColors(1, I, 1);

    DesCol := GetPlayerColor(Num[I]);

    Statics[PlayerCurrent[I]].Texture.ColR := DesCol.R;
    Statics[PlayerCurrent[I]].Texture.ColG := DesCol.G;
    Statics[PlayerCurrent[I]].Texture.ColB := DesCol.B;
  end;

  for I := 0 to UIni.IMaxPlayerCount-1 do
  begin
    Statics[PlayerCurrent[I]].Visible := I < Count;
    Text[PlayerCurrentText[I]].Visible := I < Count;
    Statics[PlayerCurrentAvatar[I]].Visible := I < Count;
  end;

  // list players
  for I := 0 to Count -1 do
  begin
    Text[PlayerCurrentText[I]].Text := PlayerNames[I];
    SetPlayerAvatar(I);
  end;

  RefreshProfile();

  AvatarTarget := PlayerAvatars[PlayerIndex];
  AvatarCurrent := AvatarTarget;

end;

procedure TScreenName.RefreshProfile();
var
  ITmp: array of UTF8String;
  Count, Max, I, J, Index: integer;
  Used: boolean;
begin
  // no-avatar for current player
  Button[PlayerAvatarButton[0]].Texture.Free;
  Button[PlayerAvatarButton[0]].Texture := NoAvatarTexture[PlayerIndex + 1].Clone();

  Button[PlayerName].Text[0].Text := PlayerNames[PlayerIndex];

  SelectsS[PlayerSelectLevel].SetSelectOpt(PlayerLevel[PlayerIndex]);

  Count := UIni.IPlayersVals[CountIndex];

  ChangeSelectPlayerPosition(PlayerIndex);

  PlayerColorButton(Num[PlayerIndex]);

  Max := Length(IPlayerColorTranslated) - Count + 1;
  SetLength(ITmp, Max);

  APlayerColor := nil;
  SetLength(APlayerColor, Max);

  Index := 0;
  for I := 0 to High(IPlayerColorTranslated) do      //for every color
  begin
    Used := false;

    for J := 0 to Count -1 do      //for every active player
    begin
      if (Num[J] - 1 = I) and (J <> PlayerIndex) then   //check if color is already used for not current player
      begin
        Used := true;
        break;
      end;
    end;

    if not (Used) then
    begin
      ITmp[Index] := IPlayerColorTranslated[I];
      APlayerColor[Index] := I + 1;
      Index := Index + 1;
    end;
  end;

  UpdateSelectSlideOptions(PlayerColor, ITmp, ColorIndex);

  for I := 0 to High(APlayerColor) do
  begin
    if (Num[PlayerIndex] = APlayerColor[I]) then
    begin
      SelectsS[PlayerColor].SetSelectOpt(I);
      break;
    end;
  end;

end;

procedure TScreenName.RefreshColor();
begin

  PlayerColorButton(APlayerColor[ColorIndex]);

end;

function TScreenName.NoRepeatColors(ColorP:integer; Interaction:integer; Pos:integer):integer;
var
  Z, Count:integer;
begin
  Count := UIni.IPlayersVals[CountIndex];

  if (ColorP > Length(IPlayerColorTranslated)) then
    ColorP := NoRepeatColors(1, Interaction, Pos);

  if (ColorP <= 0) then
    ColorP := NoRepeatColors(High(IPlayerColorTranslated), Interaction, Pos);

  for Z := Count -1 downto 0 do
  begin
    if (Num[Z] = ColorP) and (Z <> Interaction) then
      ColorP := NoRepeatColors(ColorP + Pos, Interaction, Pos)
  end;

  Result := ColorP;

end;

procedure TScreenName.PlayerColorButton(K: integer);
var
  Col, DesCol: TRGB;
begin

  Col := GetPlayerLightColor(K);

  Button[PlayerName].SelectColR:= Col.R;
  Button[PlayerName].SelectColG:= Col.G;
  Button[PlayerName].SelectColB:= Col.B;

  Button[PlayerAvatar].SelectColR:= Col.R;
  Button[PlayerAvatar].SelectColG:= Col.G;
  Button[PlayerAvatar].SelectColB:= Col.B;

  SelectsS[PlayerColor].SBGColR:= Col.R;
  SelectsS[PlayerColor].SBGColG:= Col.G;
  SelectsS[PlayerColor].SBGColB:= Col.B;

  SelectsS[PlayerSelectLevel].SBGColR:= Col.R;
  SelectsS[PlayerSelectLevel].SBGColG:= Col.G;
  SelectsS[PlayerSelectLevel].SBGColB:= Col.B;

  DesCol := GetPlayerColor(K);

  Statics[PlayerCurrent[PlayerIndex]].Texture.ColR := DesCol.R;
  Statics[PlayerCurrent[PlayerIndex]].Texture.ColG := DesCol.G;
  Statics[PlayerCurrent[PlayerIndex]].Texture.ColB := DesCol.B;

  Button[PlayerName].DeselectColR:= DesCol.R;
  Button[PlayerName].DeselectColG:= DesCol.G;
  Button[PlayerName].DeselectColB:= DesCol.B;

  Button[PlayerAvatar].DeselectColR:= DesCol.R;
  Button[PlayerAvatar].DeselectColG:= DesCol.G;
  Button[PlayerAvatar].DeselectColB:= DesCol.B;

  SelectsS[PlayerColor].SBGDColR := DesCol.R;
  SelectsS[PlayerColor].SBGDColG:= DesCol.G;
  SelectsS[PlayerColor].SBGDColB:= DesCol.B;

  SelectsS[PlayerSelectLevel].SBGDColR := DesCol.R;
  SelectsS[PlayerSelectLevel].SBGDColG:= DesCol.G;
  SelectsS[PlayerSelectLevel].SBGDColB:= DesCol.B;

  Button[PlayerAvatarButton[0]].Texture.ColR := DesCol.R;
  Button[PlayerAvatarButton[0]].Texture.ColG := DesCol.G;
  Button[PlayerAvatarButton[0]].Texture.ColB := DesCol.B;

  if (PlayerAvatars[PlayerIndex] = 0) then
  begin
    Statics[PlayerCurrentAvatar[PlayerIndex]].Texture.ColR := DesCol.R;
    Statics[PlayerCurrentAvatar[PlayerIndex]].Texture.ColG := DesCol.G;
    Statics[PlayerCurrentAvatar[PlayerIndex]].Texture.ColB := DesCol.B;
  end;

  SelectsS[PlayerColor].SetSelect(false);
  SelectsS[PlayerSelectLevel].SetSelect(false);
  Button[PlayerName].SetSelect(false);
  Button[PlayerAvatar].SetSelect(false);

  Num[PlayerIndex] := K;
  Ini.PlayerColor[PlayerIndex] := K;
end;

constructor TScreenName.Create;
var
  I: integer;
begin
  inherited Create;

  LoadFromTheme(Theme.Name);

  // Theme.Name.Text[1] (NameText2, "SING_PLAYER_DESC" subheader) -> Text[1],
  // since LoadFromTheme is the first thing populating Text[] here.
  Text[1].Visible := false;

  Theme.Name.SelectPlayersCount.oneItemOnly := true;
  Theme.Name.SelectPlayersCount.showArrows := true;
  PlayersCount := AddSelectSlide(Theme.Name.SelectPlayersCount, CountIndex, IPlayers);

  for I := 0 to UIni.IMaxPlayerCount -1 do
  begin
    PlayerCurrentAvatar[I] := AddStaticRectangle(Theme.Name.PlayerSelectAvatar[I]);
    PlayerCurrent[I] := AddStatic(Theme.Name.PlayerSelect[I]);
    PlayerCurrentText[I] := AddText(Theme.Name.PlayerSelectText[I]);
  end;

  PlayerSelect := AddButton(Theme.Name.PlayerSelectCurrent);

  PlayerAvatar := AddButton(Theme.Name.PlayerButtonAvatar);
  PlayerAvatarIID := High(Interactions);

  PlayerName := AddButton(Theme.Name.PlayerButtonName);
  Button[PlayerName].Text[0].Writable := true;

  Theme.Name.SelectPlayerColor.oneItemOnly := true;
  Theme.Name.SelectPlayerColor.showArrows := true;
  PlayerColor := AddSelectSlide(Theme.Name.SelectPlayerColor, ColorIndex, IPlayerColorTranslated);

  Theme.Name.SelectPlayerLevel.oneItemOnly := true;
  Theme.Name.SelectPlayerLevel.showArrows := true;
  PlayerSelectLevel := AddSelectSlide(Theme.Name.SelectPlayerLevel, LevelIndex, IDifficultyTranslated);

  isScrolling := false;

  GenerateAvatars();

  NumVisibleAvatars := Theme.Name.PlayerScrollAvatar.NumAvatars;
  DistanceVisibleAvatars := Theme.Name.PlayerScrollAvatar.DistanceAvatars;

  Interaction := 0;
end;

procedure TScreenName.SetPlayerAvatar(Player: integer);
var
  Col: TRGB;
begin

  if (PlayerAvatars[Player] = 0) then
  begin
    Statics[PlayerCurrentAvatar[Player]].Texture.Free;
    Statics[PlayerCurrentAvatar[Player]].Texture := NoAvatarTexture[Player + 1].Clone;

    Col := GetPlayerColor(Num[Player]);

    Statics[PlayerCurrentAvatar[Player]].Texture.ColR := Col.R;
    Statics[PlayerCurrentAvatar[Player]].Texture.ColG := Col.G;
    Statics[PlayerCurrentAvatar[Player]].Texture.ColB := Col.B;
  end
  else
  begin
    Statics[PlayerCurrentAvatar[Player]].Texture.Free;
    Statics[PlayerCurrentAvatar[Player]].Texture := Button[PlayerAvatarButton[PlayerAvatars[Player]]].Texture.Clone;
  end;

  Statics[PlayerCurrentAvatar[Player]].Texture.X := Theme.Name.PlayerSelectAvatar[Player].X;
  Statics[PlayerCurrentAvatar[Player]].Texture.Y := Theme.Name.PlayerSelectAvatar[Player].Y;
  Statics[PlayerCurrentAvatar[Player]].Texture.W := Theme.Name.PlayerSelectAvatar[Player].W;
  Statics[PlayerCurrentAvatar[Player]].Texture.H := Theme.Name.PlayerSelectAvatar[Player].H;
  Statics[PlayerCurrentAvatar[Player]].Texture.Z := Theme.Name.PlayerSelectAvatar[Player].Z;

  Statics[PlayerCurrentAvatar[Player]].Texture.Int := 1;

end;

procedure TScreenName.OnShow;
var
  I: integer;
begin
  inherited;

  Ini.ReloadNames;
  CountIndex := Ini.Players;

  for I := 0 to UIni.IMaxPlayerCount-1 do
  begin
    PlayerNames[I] := Ini.Name[I];
    PlayerLevel[I] := Ini.PlayerLevel[I];
    PlayerAvatars[I] := GetArrayIndex(PlayerAvatarButtonMD5, Ini.PlayerAvatar[I]);
    // if it is -1 then the current saved md5 does not exist anymore (file has changed or was deleted entirely)
    // setting it to 0 just resets it to the colorized default avatar
    if (PlayerAvatars[I] = -1) then
    begin
      PlayerAvatars[I] := 0;
    end;
  end;

  AvatarTarget := PlayerAvatars[PlayerIndex];
  AvatarCurrent := AvatarTarget;

  RefreshPlayers;

  // list players
  for I := 1 to PlayersPlay do
  begin
    Text[PlayerCurrentText[I - 1]].Text := Ini.Name[I - 1];
    SetPlayerAvatar(I - 1);
  end;

  PlayerColorButton(Num[PlayerIndex]);

  SelectsS[PlayersCount].SetSelectOpt(CountIndex);

  Button[PlayerName].Text[0].Text := PlayerNames[PlayerIndex];

  isScrolling := false;

  Interaction := 0;
  FRow := 0;
  FRingReady := false;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenName');
end;

procedure TScreenName.SetAvatarScroll;
var
  B:        integer;
  Angle:    real;
  Pos:      real;
  VS:       integer;
  Padding:  real;
  X:        real;
  Factor:   real;
begin

  VS := Length(AvatarsList);

  case NumVisibleAvatars of
    1: begin
        Factor := 0;
       end;
    3: begin
        Factor := 1;
       end;
    5: begin
        Factor := 1.5;
       end;
   end;

  // Update positions of all avatars
  for B := PlayerAvatarButton[0] to PlayerAvatarButton[High(AvatarsList)] do
  begin
    Button[B].Visible := true; // adjust visibility

    // Pos is the distance to the centered avatar in the range [-VS/2..+VS/2]
    Pos := (B - PlayerAvatarButton[0] - AvatarCurrent);
    if (Pos < -VS/2) then
      Pos := Pos + VS
    else if (Pos > VS/2) then
      Pos := Pos - VS;

    // Avoid overlapping of the front avatars.
    // Use an alternate position for the others.
    if (Abs(Pos) < (NumVisibleAvatars/2)) then
    begin
      if (NumVisibleAvatars > 1) then
      begin
        Angle := Pi * (Pos / Min(VS, NumVisibleAvatars)); // Range: (-1/4*Pi .. +1/4*Pi)

        Button[B].H := Abs(Theme.Name.PlayerAvatar.H * cos(Angle*0.8));
        Button[B].W := Abs(Theme.Name.PlayerAvatar.W * cos(Angle*0.8));

        //Button[B].Reflectionspacing := 15 * Button[B].H/Theme.Song.Cover.H;
        Button[B].DeSelectReflectionspacing := 15 * Button[B].H/Theme.Name.PlayerAvatar.H;

        Padding := (Button[B].W - Theme.Name.PlayerAvatar.W)/2;
        X := Sin(Angle*1.3) * 0.9;

        Button[B].X := Theme.Name.PlayerAvatar.X + (Theme.Name.PlayerAvatar.W * Factor + DistanceVisibleAvatars) * X - Padding;
        Button[B].Y := (Theme.Name.PlayerAvatar.Y  + (Theme.Name.PlayerAvatar.H - Abs(Theme.Name.PlayerAvatar.H * cos(Angle))) * 0.5);
        Button[B].Z := 0.95 - Abs(Pos) * 0.01;

        Button[B].Reflection := true;
        Button[B].Reflectionspacing := 2;

        if (B <> PlayerAvatarButton[PlayerAvatars[PlayerIndex]]) then
        begin
          Button[B].Texture.Int := 0.7;
        end
        else
        begin
          Button[B].Texture.Int := 1;
        end;
      end
      else
      begin
        Button[B].X := Theme.Name.PlayerAvatar.X;
        Button[B].Y := Theme.Name.PlayerAvatar.Y;

        AvatarCurrent := AvatarTarget;
        
        isScrolling := false;
      end

    end
    else
    begin
      Button[B].Visible := false;
    end;

  end;

end;

procedure TScreenName.SelectNext;
var
  VS:   integer;
begin

  VS := Length(AvatarsList);

  if VS > 0 then
  begin

    if (not isScrolling) and (VS > 0) then
    begin
      isScrolling := true;
    end;

    AvatarTarget := AvatarTarget + 1;

    // try to keep all at the beginning
    if AvatarTarget > VS-1 then
    begin
      AvatarTarget := AvatarTarget - VS;
      AvatarCurrent := AvatarCurrent - VS;
    end;
  end;

end;

procedure TScreenName.SelectPrev;
var
  VS:   integer;
begin

  VS := Length(AvatarsList);

  if VS > 0 then
  begin
    if (not isScrolling) and (VS > 0) then
    begin
      isScrolling := true;
    end;

    AvatarTarget := AvatarTarget - 1;

    // try to keep all at the beginning
    if AvatarTarget < 0 then
    begin
      AvatarTarget := AvatarTarget + VS;
      AvatarCurrent := AvatarCurrent + VS;
    end;
  end;

end;

function TScreenName.AvatarTexture(P: integer): TTexture;
begin
  if (PlayerAvatars[P] <= 0) or (PlayerAvatars[P] > High(PlayerAvatarButton)) then
    Result := NoAvatarTexture[P + 1]
  else
    Result := Button[PlayerAvatarButton[PlayerAvatars[P]]].Texture;
end;

// ui-v2: Midnight player setup
function TScreenName.Draw: boolean;
var
  I, N: integer;
  X, Y, W, CardW, CardH, AvS, EdY, TW: single;
  R, Ring: TMRect;
  Sel: boolean;
  Nm, Lbl: UTF8String;
  PC: TMColor;
begin
  if Ini.ReloadNames then
    OnShow;

  N := UIni.IPlayersVals[CountIndex];

  MBegin;
  MFillRect(0, 0, MUI_W, MUI_H, mcBg, 1);

  { header }
  FBackRect := MRect(PN_PAD, 34, 44, 44);
  MFillCircle(PN_PAD + 22, 56, 22, mcSurface, 1);
  MStrokeRound(PN_PAD, 34, 44, 44, 22, 1, mcBorder, 1);
  MIconBack(PN_PAD + 22, 56, 24, mcText, 1);
  MText(PN_PAD + 64, 40, 'Who''s singing?', 30, true, mcText, 1);

  { number of singers }
  MText(PN_PAD, 108, 'Singers', 16, false, mcMuted, 1);
  X := PN_PAD;
  for I := 0 to High(UIni.IPlayersVals) do
  begin
    R := MRect(X, 134, 64, 52);
    FCountRects[I] := R;
    if (I = CountIndex) then
    begin
      MFillRound(R.X, R.Y, R.W, R.H, 16, mcAccent, 1);
      MText(R.X + R.W / 2, R.Y + 15, UIni.IPlayers[I], 22, true, mcOnAccent, 1, mtaCenter);
    end
    else
    begin
      MFillRound(R.X, R.Y, R.W, R.H, 16, mcSurface, 1);
      MStrokeRound(R.X, R.Y, R.W, R.H, 16, 1, mcBorder, 1);
      MText(R.X + R.W / 2, R.Y + 15, UIni.IPlayers[I], 22, true, mcMuted, 1, mtaCenter);
    end;
    X := X + 64 + 10;
  end;

  { singer cards }
  CardW := CardSize;
  AvS := CardW - 32;
  CardH := AvS + 76;
  Y := 214;
  for I := 0 to UIni.IMaxPlayerCount - 1 do
    FCardRects[I] := MRect(0, 0, 0, 0);
  for I := 0 to N - 1 do
  begin
    Sel := (I = PlayerIndex);
    R := MRect(PN_PAD + I * (CardW + 20), Y, CardW, CardH);
    FCardRects[I] := R;

    if Sel then
      MFillRound(R.X, R.Y, R.W, R.H, 20, mcSurface2, 1)
    else
      MFillRound(R.X, R.Y, R.W, R.H, 20, mcSurface, 1);
    MStrokeRound(R.X, R.Y, R.W, R.H, 20, 1, mcBorder, 1);

    PC := PlayerMColor(Num[I]);
    if (PlayerAvatars[I] <= 0) then
    begin
      MFillRect(R.X + 16, R.Y + 16, AvS, AvS, mcBg, 1);
      MDrawTexTint(AvatarTexture(I), R.X + 16, R.Y + 16, AvS, AvS, 1, PC);
    end
    else
      MDrawTex(AvatarTexture(I), R.X + 16, R.Y + 16, AvS, AvS, 1);
    if Sel then
      MCornerMask(R.X + 16, R.Y + 16, AvS, AvS, 14, mcSurface2)
    else
      MCornerMask(R.X + 16, R.Y + 16, AvS, AvS, 14, mcSurface);

    // name with the singer's colour dot
    Nm := PlayerNames[I];
    MFillCircle(R.X + 22, R.Y + AvS + 44, 5, PC, 1);
    if (Nm = '') then
      MText(R.X + 34, R.Y + AvS + 33, 'Player ' + IntToStr(I + 1), 18, true, mcMuted, 1, mtaLeft, R.W - 50)
    else
      MText(R.X + 34, R.Y + AvS + 33, Nm, 18, true, mcText, 1, mtaLeft, R.W - 50);
  end;

  { avatar arrows on the selected singer's picture }
  R := FCardRects[PlayerIndex];
  FAvatarRect := MRect(R.X + 16, R.Y + 16, AvS, AvS);
  FAvatarPrev := MRect(R.X + 16 - 18, R.Y + 16 + AvS / 2 - 18, 36, 36);
  FAvatarNext := MRect(R.X + 16 + AvS - 18, R.Y + 16 + AvS / 2 - 18, 36, 36);

  { colour swatches for the selected singer }
  EdY := Y + CardH + 28;
  W := 104 + Length(FColorRects) * 38;
  FColorPill := MRect(PN_PAD, EdY, W, 56);
  R := FColorPill;
  MFillRound(R.X, R.Y, R.W, R.H, 28, mcSurface, 1);
  MStrokeRound(R.X, R.Y, R.W, R.H, 28, 1, mcBorder, 1);
  MText(R.X + 24, R.Y + 19, 'Colour', 15, false, mcMuted, 1);
  for I := 0 to High(FColorRects) do
  begin
    FColorRects[I] := MRect(R.X + 92 + I * 38, R.Y + 12, 32, 32);
    PC := PlayerMColor(I + 1);
    if ColorUsedByOther(I + 1) then
    begin
      // taken by another singer
      MFillCircle(FColorRects[I].X + 16, FColorRects[I].Y + 16, 9, PC, 0.3);
      FColorRects[I] := MRect(0, 0, 0, 0);
    end
    else if (Num[PlayerIndex] = I + 1) then
    begin
      MFillCircle(FColorRects[I].X + 16, FColorRects[I].Y + 16, 16, mcText, 1);
      MFillCircle(FColorRects[I].X + 16, FColorRects[I].Y + 16, 13, PC, 1);
    end
    else
      MFillCircle(FColorRects[I].X + 16, FColorRects[I].Y + 16, 12, PC, 1);
  end;

  { name field and continue }
  EdY := EdY + 56 + 20;
  FNameRect := MRect(PN_PAD, EdY, 400, 60);
  R := FNameRect;
  MFillRound(R.X, R.Y, R.W, R.H, 30, mcSurface, 1);
  MStrokeRound(R.X, R.Y, R.W, R.H, 30, 1, mcBorder, 1);
  MText(R.X + 24, R.Y + 21, 'Name', 15, false, mcMuted, 1);
  Nm := PlayerNames[PlayerIndex];
  MText(R.X + 82, R.Y + 18, Nm, 20, true, mcText, 1, mtaLeft, R.W - 110);
  if (FRow = ROW_NAME) and ((SDL_GetTicks div 500) mod 2 = 0) then
  begin
    TW := MTextW(Nm, 20, true);
    if (TW > R.W - 110) then
      TW := R.W - 110;
    MFillRect(R.X + 84 + TW, R.Y + 16, 2, 28, mcAccent, 1);
  end;

  // continue button
  if GoTo_SingScreen then
    Lbl := 'Start singing'
  else
    Lbl := 'Choose songs';
  W := MTextW(Lbl, 20, true) + 80;
  FContinueRect := MRect(MUI_W - PN_PAD - W, EdY, W, 60);
  R := FContinueRect;
  MFillRound(R.X, R.Y, R.W, R.H, 30, mcAccent, 1);
  MText(R.X + 30, R.Y + 19, Lbl, 20, true, mcOnAccent, 1);
  MIconForward(R.X + R.W - 32, R.Y + 30, 22, mcOnAccent, 1);

  { selection ring glides between rows }
  case FRow of
    0: Ring := FCountRects[CountIndex];
    1: Ring := FCardRects[PlayerIndex];
    2: Ring := FAvatarRect;
    3: Ring := FColorPill;
  else
    Ring := FNameRect;
  end;
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
  if (FRow = 0) then
    // match the rounded-square number pills
    MStrokeRound(FRingX - 6, FRingY - 6, FRingW + 12, FRingH + 12, 22, 3, mcText, 1)
  else if (FRow = 1) then
    MStrokeRound(FRingX - 6, FRingY - 6, FRingW + 12, FRingH + 12, 26, 3, mcText, 1)
  else if (FRow = 2) then
    // around the picture, matching its rounded corners
    MStrokeRound(FRingX - 5, FRingY - 5, FRingW + 10, FRingH + 10, 18, 3, mcText, 1)
  else
    MStrokeRound(FRingX - 6, FRingY - 6, FRingW + 12, FRingH + 12, (FRingH + 12) / 2, 3, mcText, 1);

  { avatar arrows, drawn on top of the selection ring }
  MFillCircle(FAvatarPrev.X + 18, FAvatarPrev.Y + 18, 18, mcSurface2, 1);
  MStrokeRound(FAvatarPrev.X, FAvatarPrev.Y, 36, 36, 18, 1, mcBorder, 1);
  MIconBack(FAvatarPrev.X + 18, FAvatarPrev.Y + 18, 18, mcText, 1);
  MFillCircle(FAvatarNext.X + 18, FAvatarNext.Y + 18, 18, mcSurface2, 1);
  MStrokeRound(FAvatarNext.X, FAvatarNext.Y, 36, 36, 18, 1, mcBorder, 1);
  MIconForward(FAvatarNext.X + 18, FAvatarNext.Y + 18, 18, mcText, 1);

  { footer }
  X := PN_PAD;
  X := X + MKeyHint(X, 682, 'Up/Down', 'move') + 22;
  X := X + MKeyHint(X, 682, 'Left/Right', 'change') + 22;
  X := X + MKeyHint(X, 682, 'Enter', 'continue') + 22;
  MKeyHint(X, 682, 'Esc', 'back');

  MEnd;
  Result := true;
end;

end.
