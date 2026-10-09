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
 *}

{
  UModernSing - Midnight (ui-v2) look for the singing screen.

  Only drawing lives here. Scoring, timing and pitch detection are the
  untouched originals; this unit just reads their state each frame:
    - CurrentSong.Tracks[0].Lines[CurrentLine]  target notes of the line
    - Player[i].Note[]                          what each singer has sung
    - LyricsState                               the current beat
    - ScreenSing.Scores.ModernPop*              the latest line rating

  The music video keeps playing full-screen underneath; legibility comes
  from dark fades at the top and bottom, tinted-glass note lanes and
  near-solid chips.
}
unit UModernSing;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  ULyrics;

// true when the Midnight singing screen is used (one screen, not a duet)
function ModernSingActive: boolean;

// position and colour the lyrics for the Midnight layout; call before the
// first lines are added (Karaoke = scoring off, bigger lyrics)
procedure ModernSetupLyrics(Lyrics: TLyricEngine; Karaoke: boolean);

// dark fades behind the top HUD and the lyrics
procedure ModernSingBackdrop;

// one tinted-glass note lane per singer
procedure ModernSingLanes;

// lyrics in Helvetica: current line big (sung part lime), next line grey,
// plus a shrinking lime "get ready" bar before a line starts
procedure ModernSingLyrics(Beat: real);

// song timeline (lyric sections + progress), singer chips, song chip and
// line-bonus pills
procedure ModernSingHud(CurTime, TotalTime: real; const TimeText: UTF8String);

implementation

uses
  SysUtils,
  Math,
  sdl2,
  UAvatars,
  UCommon,
  UGraphic,
  UIni,
  ULanguage,
  UModernUI,
  UMusic,
  UNote,
  UParty,
  URenderer,
  UScreenSingController,
  USong,
  UThemes;

const
  HUD_PAD = 32;
  LANES_TOP = 104;
  LANES_BOTTOM = 528;

function IsKaraoke: boolean;
begin
  // karaoke mode hides every note lane and the scores
  Result := not ScreenSing.Settings.NotesVisible[0] and not ScreenSing.Settings.InputVisible;
end;

function ModernSingActive: boolean;
begin
  Result := (Screens = 1) and (CurrentSong <> nil) and
            not (CurrentSong.isDuet and (PlayersPlay <> 1));
end;

procedure ModernSetupLyrics(Lyrics: TLyricEngine; Karaoke: boolean);
var
  UY, LY, H: real;
begin
  if (Lyrics = nil) then
    Exit;

  // positions are in the classic 800x600 grid the lyric engine uses
  if Karaoke then
  begin
    UY := 436;
    LY := 506;
    H := 56;
  end
  else
  begin
    UY := 470;
    LY := 520;
    H := 42;
  end;

  Lyrics.UpperLineX := 40;
  Lyrics.UpperLineW := 720;
  Lyrics.UpperLineY := UY;
  Lyrics.UpperLineH := H;
  Lyrics.LowerLineX := 40;
  Lyrics.LowerLineW := 720;
  Lyrics.LowerLineY := LY;
  Lyrics.LowerLineH := H;

  // sung part in lime, the rest of the line white, the next line grey
  Lyrics.LineColor_act.R := mcAccent.R;
  Lyrics.LineColor_act.G := mcAccent.G;
  Lyrics.LineColor_act.B := mcAccent.B;
  Lyrics.LineColor_act.A := 1;

  Lyrics.LineColor_en.R := mcText.R;
  Lyrics.LineColor_en.G := mcText.G;
  Lyrics.LineColor_en.B := mcText.B;
  Lyrics.LineColor_en.A := 1;

  Lyrics.LineColor_dis.R := mcMuted.R;
  Lyrics.LineColor_dis.G := mcMuted.G;
  Lyrics.LineColor_dis.B := mcMuted.B;
  Lyrics.LineColor_dis.A := 1;
end;

function PlayerColor(PlayerIndex: integer): TMColor;
var
  C: TRGB;
begin
  C := GetPlayerColor(Ini.SingColor[PlayerIndex]);
  Result.R := C.R;
  Result.G := C.G;
  Result.B := C.B;
end;

procedure ModernSingBackdrop;
begin
  MBegin;
  // top: behind the chips
  MFillGradientV(0, 0, MUI_W, 150, mcBg, 0.85, 0);
  // bottom: behind the lyrics
  if IsKaraoke then
  begin
    MFillGradientV(0, 380, MUI_W, 140, mcBg, 0, 0.92);
    MFillRect(0, 520, MUI_W, MUI_H - 520, mcBg, 0.92);
  end
  else
  begin
    MFillGradientV(0, 470, MUI_W, 90, mcBg, 0, 0.92);
    MFillRect(0, 560, MUI_W, MUI_H - 560, mcBg, 0.92);
  end;
  MEnd;
end;

{ --- note lanes --- }

procedure DrawLane(const R: TMRect; PlayerIndex: integer; ShowStripe: boolean);
const
  PAD_X = 24;
  PAD_Y = 14;
  SEMITONES = 18;
var
  Line: PLine;
  LenR: real;
  BeatW, Step, NH, X1, X2, Y, Pulse, LastX, LastY: single;
  N, First, I: integer;
  PC, Gold: TMColor;
  HasLast, LastActive: boolean;

  function ToneY(T: real): single;
  begin
    Result := R.Y + R.H - PAD_Y - NH / 2 - T * Step;
    if (Result < R.Y + PAD_Y + NH / 2) then
      Result := R.Y + PAD_Y + NH / 2;
    if (Result > R.Y + R.H - PAD_Y - NH / 2) then
      Result := R.Y + R.H - PAD_Y - NH / 2;
  end;

begin
  PC := PlayerColor(PlayerIndex);
  Gold := MColor($F5C542);

  // tinted glass so the video still shows through
  MFillRound(R.X, R.Y, R.W, R.H, 22, mcBg, 0.55);
  MStrokeRound(R.X, R.Y, R.W, R.H, 22, 1, mcText, 0.08);
  if ShowStripe then
    MFillRound(R.X, R.Y + 10, 5, R.H - 20, 2.5, PC, 1);

  // faint pitch guide lines
  if (Ini.NoteLines = 1) then
    for I := 1 to 8 do
      MFillRect(R.X + PAD_X, R.Y + PAD_Y + I * (R.H - 2 * PAD_Y) / 9, R.W - 2 * PAD_X, 1, mcText, 0.07);

  if (Length(CurrentSong.Tracks) = 0) then
    Exit;
  if (CurrentSong.Tracks[0].CurrentLine < 0) or
     (CurrentSong.Tracks[0].CurrentLine > High(CurrentSong.Tracks[0].Lines)) then
    Exit;

  Line := @CurrentSong.Tracks[0].Lines[CurrentSong.Tracks[0].CurrentLine];
  if (not Line^.HasLength(LenR)) or (LenR <= 0) or (Line^.HighNote < 0) then
    Exit;

  BeatW := (R.W - 2 * PAD_X) / LenR;
  NH := (R.H - 2 * PAD_Y) / SEMITONES * 1.6;
  if (NH < 8) then
    NH := 8;
  if (NH > 18) then
    NH := 18;
  Step := (R.H - 2 * PAD_Y - NH) / SEMITONES;
  First := Line^.Notes[0].StartBeat;
  Pulse := 0.5 + 0.5 * Sin(SDL_GetTicks / 300);

  // the notes to sing
  if ScreenSing.Settings.NotesVisible[PlayerIndex] then
    for N := 0 to Line^.HighNote do
      with Line^.Notes[N] do
      begin
        if (NoteType = ntFreestyle) then
          Continue;
        X1 := R.X + PAD_X + (StartBeat - First) * BeatW;
        X2 := R.X + PAD_X + (StartBeat + Duration - First) * BeatW - 2;
        if (X2 < X1 + 2) then
          X2 := X1 + 2;
        Y := ToneY(Tone - Line^.BaseNote);

        if (NoteType = ntGolden) or (NoteType = ntRapGolden) then
        begin
          MFillRound(X1 - 5, Y - NH / 2 - 5, X2 - X1 + 10, NH + 10, (NH + 10) / 2, Gold, 0.15 + 0.2 * Pulse);
          MFillRound(X1, Y - NH / 2, X2 - X1, NH, NH / 2, Gold, 1);
        end
        else if (NoteType = ntRap) then
          MStrokeRound(X1, Y - NH / 2, X2 - X1, NH, NH / 2, 2, mcText, 0.85)
        else
          MFillRound(X1, Y - NH / 2, X2 - X1, NH, NH / 2, mcText, 0.85);
      end;

  // what this singer has sung, in their colour
  HasLast := false;
  LastActive := false;
  LastX := 0;
  LastY := 0;
  if ScreenSing.Settings.InputVisible and (PlayerIndex <= High(Player)) then
    for N := 0 to Player[PlayerIndex].HighNote do
      with Player[PlayerIndex].Note[N] do
      begin
        X1 := R.X + PAD_X + (Start - First) * BeatW;
        X2 := R.X + PAD_X + (Start + Duration - First) * BeatW - 2;
        // the note being sung right now grows smoothly
        if (Start + Duration - 1 = LyricsState.CurrentBeatD) then
          X2 := X2 - (1 - Frac(LyricsState.MidBeatD)) * BeatW;
        if (X2 < X1 + 2) then
          X2 := X1 + 2;
        Y := ToneY(Tone - Line^.BaseNote);

        if Hit then
          MFillRound(X1, Y - NH / 2, X2 - X1, NH, NH / 2, PC, 1)
        else
          MFillRound(X1, Y - NH * 0.3, X2 - X1, NH * 0.6, NH * 0.3, PC, 0.45);

        HasLast := true;
        LastX := X2;
        LastY := Y;
        LastActive := (Start + Duration >= LyricsState.CurrentBeatD);
      end;

  // pitch marker at the tip of the current note
  if HasLast and LastActive then
  begin
    MFillCircle(LastX, LastY, NH * 0.75, mcText, 1);
    MFillCircle(LastX, LastY, NH * 0.5, PC, 1);
  end;
end;

procedure ModernSingLanes;
var
  N, I, Cols, Rows, Col, Row: integer;
  AreaW, AreaH, LaneW, LaneH, Gap: single;
  R: TMRect;
begin
  if IsKaraoke then
    Exit;

  N := PlayersPlay;
  if (N < 1) then
    N := 1;

  MBegin;

  if (N = 1) then
  begin
    R := MRect(HUD_PAD, 214, MUI_W - 2 * HUD_PAD, 250);
    DrawLane(R, 0, false);
  end
  else
  begin
    if (N <= 3) then
      Cols := 1
    else
      Cols := 2;
    Rows := (N + Cols - 1) div Cols;
    Gap := 14;
    AreaW := MUI_W - 2 * HUD_PAD;
    AreaH := LANES_BOTTOM - LANES_TOP;
    LaneW := (AreaW - (Cols - 1) * Gap) / Cols;
    LaneH := (AreaH - (Rows - 1) * Gap) / Rows;
    for I := 0 to N - 1 do
    begin
      // like the classic layout: P1, P2 down the left, then the right column
      Col := I div Rows;
      Row := I mod Rows;
      R := MRect(HUD_PAD + Col * (LaneW + Gap), LANES_TOP + Row * (LaneH + Gap), LaneW, LaneH);
      DrawLane(R, I, true);
    end;
  end;

  MEnd;
end;

{ --- lyrics --- }

procedure DrawLyricLine(Line: TLyricLine; CenterX, Y, Size: single; Beat: real; Active: boolean);
var
  I, N: integer;
  Total, X, S, Fr: single;
  SoFar: UTF8String;
  Pos, Wid: array of single;
  Shadow: TMColor;
begin
  if (Line = nil) then
    Exit;
  N := Length(Line.Words);
  if (N = 0) then
    Exit;

  // shrink long lines to fit the screen
  S := Size;
  Total := MTextW(Line.Text, S, true);
  if (Total > MUI_W - 120) and (Total > 0) then
  begin
    S := S * (MUI_W - 120) / Total;
    Total := MTextW(Line.Text, S, true);
  end;
  X := CenterX - Total / 2;

  // word positions (same method as the classic lyric engine)
  SetLength(Pos, N);
  SetLength(Wid, N);
  SoFar := '';
  for I := 0 to N - 1 do
  begin
    Wid[I] := MTextW(Line.Words[I].Text, S, true);
    SoFar := SoFar + Line.Words[I].Text;
    Pos[I] := X + MTextW(SoFar, S, true) - Wid[I];
  end;

  // soft shadow for very bright video frames
  Shadow := MColor($000000);
  for I := 0 to N - 1 do
    MText(Pos[I] + 2, Y + 2, Line.Words[I].Text, S, true, Shadow, 0.55);

  for I := 0 to N - 1 do
  begin
    if not Active then
      MText(Pos[I], Y, Line.Words[I].Text, S, true, mcMuted, 1)
    else if (Beat >= Line.Words[I].Start + Line.Words[I].Length) then
      MText(Pos[I], Y, Line.Words[I].Text, S, true, mcAccent, 1)
    else if (Beat <= Line.Words[I].Start) or (Line.Words[I].Length <= 0) then
      MText(Pos[I], Y, Line.Words[I].Text, S, true, mcText, 1)
    else
    begin
      // the word being sung fills in lime from left to right
      MText(Pos[I], Y, Line.Words[I].Text, S, true, mcText, 1);
      Fr := (Beat - Line.Words[I].Start) / Line.Words[I].Length;
      MClipBegin(MRect(Pos[I], Y - S * 0.5, Wid[I] * Fr, S * 2));
      MText(Pos[I], Y, Line.Words[I].Text, S, true, mcAccent, 1);
      MClipEnd;
    end;
  end;
end;

procedure ModernSingLyrics(Beat: real);
const
  MOVE_LIMIT = 40; // beats, as in the classic helper
var
  CurSize, CurY, NextSize, NextY, Fr, BW: single;
  CurLine: PLine;
  FirstNoteBeat, FirstNoteDelta: integer;
  BarDelta: real;
begin
  if not ScreenSing.Settings.LyricsVisible then
    Exit;

  if IsKaraoke then
  begin
    CurSize := 54;
    CurY := 518;
    NextSize := 30;
    NextY := 596;
  end
  else
  begin
    CurSize := 40;
    CurY := 566;
    NextSize := 24;
    NextY := 626;
  end;

  MBegin;

  // "get ready": a lime bar that shrinks away until the line starts
  if (Length(CurrentSong.Tracks) > 0) and
     (CurrentSong.Tracks[0].CurrentLine >= 0) and
     (CurrentSong.Tracks[0].CurrentLine <= High(CurrentSong.Tracks[0].Lines)) then
  begin
    CurLine := @CurrentSong.Tracks[0].Lines[CurrentSong.Tracks[0].CurrentLine];
    if (Length(CurLine^.Notes) > 0) then
    begin
      FirstNoteBeat := CurLine^.Notes[0].StartBeat;
      FirstNoteDelta := FirstNoteBeat - CurLine^.StartBeat;
      BarDelta := FirstNoteBeat - LyricsState.MidBeat;
      if (FirstNoteDelta > 8) and (BarDelta > 0) then
      begin
        if (BarDelta > MOVE_LIMIT) then
          BarDelta := MOVE_LIMIT;
        if (FirstNoteDelta > MOVE_LIMIT) then
          FirstNoteDelta := MOVE_LIMIT;
        Fr := BarDelta / FirstNoteDelta;
        BW := 220 * Fr;
        if (BW > 6) then
          MFillRound(MUI_W / 2 - BW / 2, CurY - 22, BW, 6, 3, mcAccent, 0.9);
      end;
    end;
  end;

  DrawLyricLine(ScreenSing.Lyrics.GetUpperLine(), MUI_W / 2, CurY, CurSize, Beat, true);
  DrawLyricLine(ScreenSing.Lyrics.GetLowerLine(), MUI_W / 2, NextY, NextSize, Beat, false);

  MEnd;
end;

{ --- HUD --- }

// thin timeline along the top: lyric sections, filled lime as the song plays
procedure DrawTimeline(CurTime, TotalTime: real);
const
  BAR_H = 6;
var
  SongStart, SongEnd, SongDur, Gap, Prog, X, W: real;
  LineIndex: integer;
  Ln: PLine;
  pass: integer;
  C: TMColor;
begin
  if (CurrentSong.BPM <= 0) or (TotalTime <= 0) then
    Exit;

  SongStart := CurrentSong.BPM * CurrentSong.Start / 60;
  SongEnd := CurrentSong.BPM * TotalTime / 60;
  SongDur := SongEnd - SongStart;
  if (SongDur <= 0) then
    Exit;
  Gap := CurrentSong.BPM * CurrentSong.GAP / 1000 / 60;
  Prog := (CurrentSong.BPM * CurTime / 60 - SongStart) / SongDur;
  if (Prog < 0) then Prog := 0;
  if (Prog > 1) then Prog := 1;

  MFillRect(0, 0, MUI_W, BAR_H, mcBg, 0.6);

  // pass 0: all sections in white; pass 1: the part already played in lime
  for pass := 0 to 1 do
  begin
    if (pass = 1) then
    begin
      MClipBegin(MRect(0, 0, MUI_W * Prog, BAR_H));
      MFillRect(0, 0, MUI_W * Prog, BAR_H, mcAccent, 0.35);
      C := mcAccent;
    end
    else
      C := mcText;

    if (Length(CurrentSong.Tracks) > 0) then
      for LineIndex := 0 to High(CurrentSong.Tracks[0].Lines) do
      begin
        Ln := @CurrentSong.Tracks[0].Lines[LineIndex];
        if (Length(Ln^.Notes) = 0) or (Ln^.HighNote < 0) then
          Continue;
        X := (Gap + Ln^.Notes[0].StartBeat - SongStart) / SongDur * MUI_W;
        W := (Ln^.Notes[Ln^.HighNote].StartBeat + Ln^.Notes[Ln^.HighNote].Duration -
              Ln^.Notes[0].StartBeat) / SongDur * MUI_W;
        if (W < 2) then
          W := 2;
        if (pass = 0) then
          MFillRect(X, 0, W, BAR_H, C, 0.45)
        else
          MFillRect(X, 0, W, BAR_H, C, 1);
      end;

    if (pass = 1) then
      MClipEnd;
  end;
end;


function PopupText(Rating: integer): UTF8String;
begin
  case Rating of
    8: Result := Language.Translate('POPUP_PERFECT');
    7: Result := Language.Translate('POPUP_AWESOME');
    6: Result := Language.Translate('POPUP_GREAT');
    5: Result := Language.Translate('POPUP_GOOD');
    4: Result := Language.Translate('POPUP_NOTBAD');
    3: Result := Language.Translate('POPUP_BAD');
    2: Result := Language.Translate('POPUP_POOR');
  else
    Result := Language.Translate('POPUP_AWFUL');
  end;
end;

// singer chip: avatar, name and score; AlignRight puts the avatar on the right
procedure DrawPlayerChip(X, Y, W: single; PlayerIndex: integer; AlignRight, ShowScore: boolean);
const
  H = 56;
  AV = 44;
var
  Tex: TTexture;
  TC, PC: TMColor;
  AX, TX: single;
  Name: UTF8String;
begin
  PC := PlayerColor(PlayerIndex);
  MFillRound(X, Y, W, H, H / 2, mcSurface, 0.9);
  MStrokeRound(X, Y, W, H, H / 2, 1, mcBorder, 1);

  if AlignRight then
    AX := X + W - 6 - AV
  else
    AX := X + 6;

  // avatar (or the singer's colour) in a circle
  Tex := AvatarPlayerTextures[PlayerIndex + 1];
  if (Tex <> nil) and not Tex.IsEmpty then
  begin
    TC.R := Tex.ColR; TC.G := Tex.ColG; TC.B := Tex.ColB;
    MFillCircle(AX + AV / 2, Y + H / 2, AV / 2, PC, 1);
    MDrawTexTint(Tex, AX, Y + 6, AV, AV, 1, TC);
    MCornerMask(AX, Y + 6, AV, AV, AV / 2, mcSurface);
  end
  else
    MFillCircle(AX + AV / 2, Y + H / 2, AV / 2, PC, 1);

  Name := Player[PlayerIndex].Name;
  if AlignRight then
  begin
    TX := AX - 14;
    if ShowScore then
    begin
      MText(TX, Y + 8, Name, 14, false, mcMuted, 1, mtaRight, W - AV - 40);
      MText(TX, Y + 25, IntToStr(Player[PlayerIndex].ScoreTotalInt), 22, true, mcText, 1, mtaRight);
    end
    else
      MText(TX, Y + 18, Name, 18, true, mcText, 1, mtaRight, W - AV - 40);
  end
  else
  begin
    TX := AX + AV + 14;
    if ShowScore then
    begin
      MText(TX, Y + 8, Name, 14, false, mcMuted, 1, mtaLeft, W - AV - 40);
      MText(TX, Y + 25, IntToStr(Player[PlayerIndex].ScoreTotalInt), 22, true, mcText, 1);
    end
    else
      MText(TX, Y + 18, Name, 18, true, mcText, 1, mtaLeft, W - AV - 40);
  end;
end;

// line-bonus pill under a chip, shown for a moment after each line
procedure DrawPopup(X, Y: single; PlayerIndex: integer; AlignRight: boolean);
const
  SHOW_MS = 1600;
  FADE_MS = 400;
var
  Age: cardinal;
  A, W: single;
  Txt: UTF8String;
  Good: boolean;
begin
  if (PlayerIndex > High(ScreenSing.Scores.ModernPopTime)) then
    Exit;
  if (ScreenSing.Scores.ModernPopTime[PlayerIndex] = 0) then
    Exit;
  Age := SDL_GetTicks - ScreenSing.Scores.ModernPopTime[PlayerIndex];
  if (Age > SHOW_MS) then
    Exit;

  A := 1;
  if (Age > SHOW_MS - FADE_MS) then
    A := (SHOW_MS - Age) / FADE_MS;

  Txt := PopupText(ScreenSing.Scores.ModernPopRating[PlayerIndex]);
  if (ScreenSing.Scores.ModernPopDiff[PlayerIndex] > 0) then
    Txt := Txt + '  +' + IntToStr(ScreenSing.Scores.ModernPopDiff[PlayerIndex]);
  Good := (ScreenSing.Scores.ModernPopRating[PlayerIndex] >= 6);

  W := MTextW(Txt, 16, true) + 36;
  if AlignRight then
    X := X - W;
  if Good then
  begin
    MFillRound(X, Y, W, 36, 18, mcAccent, A);
    MText(X + 18, Y + 10, Txt, 16, true, mcOnAccent, A);
  end
  else
  begin
    MFillRound(X, Y, W, 36, 18, mcSurface, 0.9 * A);
    MText(X + 18, Y + 10, Txt, 16, true, mcText, A);
  end;
end;

procedure DrawSongChip(X, Y: single; AlignRight: boolean; const TimeText: UTF8String);
var
  Title, Artist: UTF8String;
  W, TW, AW, MW: single;
begin
  Title := CurrentSong.Title;
  Artist := CurrentSong.Artist;
  TW := MTextW(Title, 16, true);
  if (TW > 360) then
    TW := 360;
  AW := MTextW(Artist, 16, false);
  if (AW > 260) then
    AW := 260;
  MW := MTextW(TimeText, 16, false);
  W := 22 + TW + 16 + AW + 16 + MW + 22;
  if AlignRight then
    X := X - W;

  MFillRound(X, Y, W, 48, 24, mcSurface, 0.9);
  MStrokeRound(X, Y, W, 48, 24, 1, mcBorder, 1);
  MText(X + 22, Y + 15, Title, 16, true, mcText, 1, mtaLeft, 360);
  MText(X + 22 + TW + 16, Y + 15, Artist, 16, false, mcMuted, 1, mtaLeft, 260);
  MText(X + 22 + TW + 16 + AW + 16, Y + 15, TimeText, 16, false, mcMuted, 1);
end;

procedure ModernSingHud(CurTime, TotalTime: real; const TimeText: UTF8String);
var
  N, I: integer;
  ShowScore, Scoring: boolean;
  ChipW, X: single;
begin
  MBegin;

  // song timeline with the lyric sections along the very top
  if ScreenSing.Settings.TimeBarVisible then
    DrawTimeline(CurTime, TotalTime);

  Scoring := ScreenSing.Settings.ScoresVisible and not IsKaraoke;
  ShowScore := Scoring and ((Ini.SingScores = 1) or Party.bPartyGame);
  N := PlayersPlay;

  if not Scoring then
  begin
    // scoring off: just the song
    DrawSongChip(HUD_PAD, 28, false, TimeText);
  end
  else if (N = 1) then
  begin
    DrawPlayerChip(HUD_PAD, 22, 220, 0, false, ShowScore);
    DrawPopup(HUD_PAD, 90, 0, false);
    DrawSongChip(MUI_W - HUD_PAD, 26, true, TimeText);
  end
  else if (N = 2) then
  begin
    DrawPlayerChip(HUD_PAD, 22, 220, 0, false, ShowScore);
    DrawPlayerChip(MUI_W - HUD_PAD - 220, 22, 220, 1, true, ShowScore);
    DrawPopup(HUD_PAD, 86, 0, false);
    DrawPopup(MUI_W - HUD_PAD, 86, 1, true);
    MText(MUI_W / 2, 40, CurrentSong.Title + '   ' + TimeText, 15, false, mcMuted, 1, mtaCenter, MUI_W - 560);
  end
  else
  begin
    // three or more: a row of chips across the top
    ChipW := (MUI_W - 2 * HUD_PAD - (N - 1) * 10) / N;
    for I := 0 to N - 1 do
    begin
      X := HUD_PAD + I * (ChipW + 10);
      DrawPlayerChip(X, 22, ChipW, I, false, ShowScore);
    end;
  end;

  MEnd;
end;

end.
