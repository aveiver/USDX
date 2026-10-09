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
  UModernUI - drawing toolkit for the "Midnight" UI (ui-v2).

  The rest of the game draws on a fixed 800x600 grid that is stretched onto
  the window. The modern menus instead draw on a virtual canvas that is
  always 720 units tall and as wide as the window's aspect ratio needs
  (1280 on a 16:9 screen), so nothing is stretched.

  Usage inside a screen's Draw:
    MBegin;            // switch to the virtual canvas
    ... MFillRound / MText / MDrawTex ...
    MEnd;              // back to the 800x600 grid for popups etc.
}
unit UModernUI;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  URenderer;

type
  TMColor = record
    R, G, B: single;
  end;

  TMRect = record
    X, Y, W, H: single;
  end;

  TMLines = array of UTF8String;

const
  MUI_H = 720.0;

  // text alignment
  mtaLeft   = 0;
  mtaCenter = 1;
  mtaRight  = 2;

var
  // width of the virtual canvas, updated by MBegin (1280 on 16:9)
  MUI_W: single = 1280;

  // Midnight palette
  mcBg:        TMColor;  // page background
  mcSurface:   TMColor;  // cards
  mcSurface2:  TMColor;  // selected list row
  mcBorder:    TMColor;  // hairlines
  mcText:      TMColor;  // primary text
  mcMuted:     TMColor;  // secondary text
  mcAccent:    TMColor;  // lime accent
  mcOnAccent:  TMColor;  // text on the accent
  mcGood:      TMColor;  // "ready" dots

function MColor(Hex: cardinal): TMColor;
function MRect(X, Y, W, H: single): TMRect;
function MLerpColor(const A, B: TMColor; T: single): TMColor;

procedure MBegin;
procedure MEnd;

// virtual canvas <-> other coordinate systems
procedure MWindowToVirtual(WinX, WinY: integer; out VX, VY: single);
function MVirtualToRender(const R: TMRect): TMRect;
function MHit(VX, VY: single; const R: TMRect): boolean;

// clip drawing to a rectangle of the virtual canvas
procedure MClipBegin(const R: TMRect);
procedure MClipEnd;

// shapes
procedure MFillRect(X, Y, W, H: single; const C: TMColor; A: single);
procedure MFillRound(X, Y, W, H, Radius: single; const C: TMColor; A: single);
procedure MStrokeRound(X, Y, W, H, Radius, Thick: single; const C: TMColor; A: single);
procedure MFillCircle(CX, CY, Radius: single; const C: TMColor; A: single);
// paints the four corners outside a rounded rect in Bg, to round off a texture
procedure MCornerMask(X, Y, W, H, Radius: single; const Bg: TMColor);

// textures (covers)
procedure MDrawTex(Tex: TTexture; X, Y, W, H, A: single);

// text; Y is the top of the line. Size is roughly the cap-to-descender height.
function MTextW(const S: UTF8String; Size: single; Bold: boolean): single;
procedure MText(X, Y: single; const S: UTF8String; Size: single; Bold: boolean;
  const C: TMColor; A: single; Align: integer = mtaLeft; MaxW: single = 0);

// word-wraps S to lines no wider than MaxW (also splits on line breaks and '\n')
function MWrap(const S: UTF8String; Size: single; Bold: boolean; MaxW: single): TMLines;

// centred dialog card with a dimmed backdrop; Rects receives the button areas
procedure MDialog(const Title, Msg: UTF8String; const Captions: array of UTF8String;
  Selected: integer; var Rects: array of TMRect);

// key hint like "[Enter] select"; returns the width used
function MKeyHint(X, Y: single; const Key, Caption: UTF8String): single;

// icons (stroke style, drawn with lines)
procedure MIconPlay(CX, CY, Size: single; const C: TMColor; A: single);
procedure MIconNote(CX, CY, Size: single; const C: TMColor; A: single);
procedure MIconBack(CX, CY, Size: single; const C: TMColor; A: single);
procedure MIconSearch(CX, CY, Size: single; const C: TMColor; A: single);
procedure MIconMic(CX, CY, Size: single; const C: TMColor; A: single);

// smooth movement: moves Cur towards Target, frame-rate independent
function MApproach(Cur, Target, Speed: single): single;

implementation

uses
  Math,
  SysUtils,
  UGraphic,
  UText,
  UTime,
  UUnicodeUtils;

const
  ARC_SEGMENTS = 8;

var
  SavedDepthTest: boolean;
  HelveticaFamily: integer = -2; // -2 = not looked up yet

function MColor(Hex: cardinal): TMColor;
begin
  Result.R := ((Hex shr 16) and $FF) / 255;
  Result.G := ((Hex shr 8) and $FF) / 255;
  Result.B := (Hex and $FF) / 255;
end;

function MRect(X, Y, W, H: single): TMRect;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function MLerpColor(const A, B: TMColor; T: single): TMColor;
begin
  Result.R := A.R + (B.R - A.R) * T;
  Result.G := A.G + (B.G - A.G) * T;
  Result.B := A.B + (B.B - A.B) * T;
end;

procedure MBegin;
begin
  if (ScreenH > 0) and (ScreenWPerScreen > 0) then
    MUI_W := MUI_H * ScreenWPerScreen / ScreenH
  else
    MUI_W := 1280;
  // never narrower than 4:3
  if (MUI_W < 960) then
    MUI_W := 960;

  SavedDepthTest := Renderer.DepthTest;
  Renderer.DepthTest := false;
  Renderer.SetOrthographicProjection(0, MUI_W, MUI_H, 0, -1, 100);
end;

procedure MEnd;
begin
  Renderer.SetOrthographicProjection(0, RenderW, RenderH, 0, -1, 100);
  Renderer.DepthTest := SavedDepthTest;
end;

procedure MWindowToVirtual(WinX, WinY: integer; out VX, VY: single);
var
  PerScreen: integer;
begin
  PerScreen := ScreenWPerScreen;
  if (PerScreen <= 0) then
    PerScreen := 1;
  WinX := WinX mod PerScreen;
  VX := WinX / PerScreen * MUI_W;
  if (ScreenH > 0) then
    VY := WinY / ScreenH * MUI_H
  else
    VY := 0;
end;

function MVirtualToRender(const R: TMRect): TMRect;
begin
  Result.X := R.X * RenderW / MUI_W;
  Result.W := R.W * RenderW / MUI_W;
  Result.Y := R.Y * RenderH / MUI_H;
  Result.H := R.H * RenderH / MUI_H;
end;

function MHit(VX, VY: single; const R: TMRect): boolean;
begin
  Result := (VX >= R.X) and (VX <= R.X + R.W) and (VY >= R.Y) and (VY <= R.Y + R.H);
end;

procedure MClipBegin(const R: TMRect);
var
  PX, PY, PW, PH: integer;
begin
  PX := Round(R.X / MUI_W * ScreenWPerScreen) + (ScreenAct - 1) * ScreenWPerScreen;
  PW := Round(R.W / MUI_W * ScreenWPerScreen);
  PH := Round(R.H / MUI_H * ScreenH);
  PY := ScreenH - Round((R.Y + R.H) / MUI_H * ScreenH);
  if (PW < 0) then PW := 0;
  if (PH < 0) then PH := 0;
  Renderer.SetScissorRect(PX, PY, cardinal(PW), cardinal(PH));
  Renderer.ScissorTest := true;
end;

procedure MClipEnd;
begin
  Renderer.ScissorTest := false;
end;

{ --- shapes --- }

procedure MFillRect(X, Y, W, H: single; const C: TMColor; A: single);
begin
  Renderer.DrawQuad(X, Y, 0, W, H, C.R, C.G, C.B, A);
end;

// perimeter of a rounded rect, clockwise, starting at the top-left arc
procedure RoundPerimeter(X, Y, W, H, Radius: single; out PX, PY: array of single);
var
  Corner, I, N: integer;
  CX, CY, Ang: single;
begin
  N := 0;
  for Corner := 0 to 3 do
  begin
    case Corner of
      0: begin CX := X + Radius;     CY := Y + Radius;     end; // top-left
      1: begin CX := X + W - Radius; CY := Y + Radius;     end; // top-right
      2: begin CX := X + W - Radius; CY := Y + H - Radius; end; // bottom-right
    else begin CX := X + Radius;     CY := Y + H - Radius; end; // bottom-left
    end;
    for I := 0 to ARC_SEGMENTS do
    begin
      // top-left arc goes from 180 to 270 degrees, then +90 per corner
      Ang := (180 + Corner * 90 + I * 90 / ARC_SEGMENTS) * Pi / 180;
      PX[N] := CX + Cos(Ang) * Radius;
      PY[N] := CY + Sin(Ang) * Radius;
      Inc(N);
    end;
  end;
end;

function ClampRadius(W, H, Radius: single): single;
begin
  Result := Radius;
  if (Result > W / 2) then Result := W / 2;
  if (Result > H / 2) then Result := H / 2;
  if (Result < 0) then Result := 0;
end;

procedure SetTri(var T: TTriangle; X1, Y1, X2, Y2, X3, Y3: single; const C: TMColor; A: single);
begin
  T.X1 := X1; T.Y1 := Y1;
  T.X2 := X2; T.Y2 := Y2;
  T.X3 := X3; T.Y3 := Y3;
  T.Z := 0;
  T.ColR := C.R;
  T.ColG := C.G;
  T.ColB := C.B;
  T.Alpha := A;
end;

procedure MFillRound(X, Y, W, H, Radius: single; const C: TMColor; A: single);
const
  NP = 4 * (ARC_SEGMENTS + 1);
var
  PX, PY: array[0..NP - 1] of single;
  Tris: TTriangleList;
  I, J: integer;
  MX, MY: single;
begin
  if (W <= 0) or (H <= 0) then
    Exit;
  Radius := ClampRadius(W, H, Radius);
  if (Radius < 0.5) then
  begin
    MFillRect(X, Y, W, H, C, A);
    Exit;
  end;

  RoundPerimeter(X, Y, W, H, Radius, PX, PY);
  MX := X + W / 2;
  MY := Y + H / 2;
  SetLength(Tris, NP);
  for I := 0 to NP - 1 do
  begin
    J := (I + 1) mod NP;
    SetTri(Tris[I], MX, MY, PX[I], PY[I], PX[J], PY[J], C, A);
  end;
  Renderer.DrawTriangles(Tris);
end;

procedure MStrokeRound(X, Y, W, H, Radius, Thick: single; const C: TMColor; A: single);
const
  NP = 4 * (ARC_SEGMENTS + 1);
var
  OX, OY, IX, IY: array[0..NP - 1] of single;
  Tris: TTriangleList;
  I, J: integer;
  InnerR: single;
begin
  if (W <= 0) or (H <= 0) or (Thick <= 0) then
    Exit;
  Radius := ClampRadius(W, H, Radius);
  InnerR := Radius - Thick;
  if (InnerR < 0) then
    InnerR := 0;

  RoundPerimeter(X, Y, W, H, Radius, OX, OY);
  RoundPerimeter(X + Thick, Y + Thick, W - 2 * Thick, H - 2 * Thick, InnerR, IX, IY);

  SetLength(Tris, NP * 2);
  for I := 0 to NP - 1 do
  begin
    J := (I + 1) mod NP;
    SetTri(Tris[I * 2],     OX[I], OY[I], OX[J], OY[J], IX[I], IY[I], C, A);
    SetTri(Tris[I * 2 + 1], OX[J], OY[J], IX[J], IY[J], IX[I], IY[I], C, A);
  end;
  Renderer.DrawTriangles(Tris);
end;

procedure MFillCircle(CX, CY, Radius: single; const C: TMColor; A: single);
begin
  MFillRound(CX - Radius, CY - Radius, Radius * 2, Radius * 2, Radius, C, A);
end;

procedure MCornerMask(X, Y, W, H, Radius: single; const Bg: TMColor);
var
  Corner, I, N: integer;
  KX, KY, CX, CY, Ang: single;
  Tris: TTriangleList;
  AX, AY: array[0..ARC_SEGMENTS] of single;
begin
  Radius := ClampRadius(W, H, Radius);
  if (Radius < 0.5) then
    Exit;

  SetLength(Tris, 4 * ARC_SEGMENTS);
  N := 0;
  for Corner := 0 to 3 do
  begin
    case Corner of
      0: begin KX := X;     KY := Y;     CX := X + Radius;     CY := Y + Radius;     end;
      1: begin KX := X + W; KY := Y;     CX := X + W - Radius; CY := Y + Radius;     end;
      2: begin KX := X + W; KY := Y + H; CX := X + W - Radius; CY := Y + H - Radius; end;
    else begin KX := X;     KY := Y + H; CX := X + Radius;     CY := Y + H - Radius; end;
    end;
    for I := 0 to ARC_SEGMENTS do
    begin
      Ang := (180 + Corner * 90 + I * 90 / ARC_SEGMENTS) * Pi / 180;
      AX[I] := CX + Cos(Ang) * Radius;
      AY[I] := CY + Sin(Ang) * Radius;
    end;
    // fan from the sharp corner over the arc fills the area outside the arc
    for I := 0 to ARC_SEGMENTS - 1 do
    begin
      SetTri(Tris[N], KX, KY, AX[I], AY[I], AX[I + 1], AY[I + 1], Bg, 1);
      Inc(N);
    end;
  end;
  Renderer.DrawTriangles(Tris);
end;

procedure MDrawTex(Tex: TTexture; X, Y, W, H, A: single);
begin
  if (Tex = nil) or Tex.IsEmpty then
    Exit;
  Tex.X := X;
  Tex.Y := Y;
  Tex.Z := 0;
  Tex.W := W;
  Tex.H := H;
  Tex.Int := 1;
  Tex.ColR := 1;
  Tex.ColG := 1;
  Tex.ColB := 1;
  Tex.Alpha := A;
  Tex.AlphaGradient := gdNone;
  Tex.Reflection := false;
  Renderer.DrawTexture(Tex);
end;

{ --- text --- }

function FindHelvetica: integer;
var
  I: integer;
begin
  if (HelveticaFamily = -2) then
  begin
    HelveticaFamily := 0;
    for I := 0 to High(FontFamilyNames) do
      if SameText(FontFamilyNames[I], 'Helvetica') then
      begin
        HelveticaFamily := I;
        Break;
      end;
  end;
  Result := HelveticaFamily;
end;

procedure SelectFont(Size: single; Bold: boolean);
begin
  SetFontFamily(FindHelvetica);
  if not Bold then
    SetFontStyle(ftRegular)
  else if (Size >= 34) then
    SetFontStyle(ftBoldHighRes) // sharper glyphs for headings
  else
    SetFontStyle(ftBold);
  SetFontItalic(false);
  SetFontReflection(false, 0);
  SetFontZ(0);
  SetFontSize(Size);
end;

function MTextW(const S: UTF8String; Size: single; Bold: boolean): single;
var
  Old: TFont;
begin
  Old := CurrentFont;
  SelectFont(Size, Bold);
  Result := TextWidth(S);
  SetFont(Old);
end;

procedure MText(X, Y: single; const S: UTF8String; Size: single; Bold: boolean;
  const C: TMColor; A: single; Align: integer; MaxW: single);
var
  Old: TFont;
  Txt: UTF8String;
  W: single;
  Len: integer;
begin
  if (S = '') then
    Exit;

  Old := CurrentFont;
  SelectFont(Size, Bold);

  Txt := S;
  W := TextWidth(Txt);
  if (MaxW > 0) and (W > MaxW) then
  begin
    // shorten with an ellipsis until it fits
    Len := LengthUTF8(Txt);
    while (Len > 1) and (W > MaxW) do
    begin
      Dec(Len);
      Txt := TrimRight(UTF8Copy(S, 1, Len)) + '...';
      W := TextWidth(Txt);
    end;
  end;

  case Align of
    mtaCenter: X := X - W / 2;
    mtaRight:  X := X - W;
  end;

  SetFontColor(C.R, C.G, C.B, A);
  SetFontPos(X, Y);
  PrintText(Txt);

  SetFont(Old);
end;

function MWrap(const S: UTF8String; Size: single; Bold: boolean; MaxW: single): TMLines;
var
  Acc: TMLines;
  Txt, Para, Wd, Line: UTF8String;
  P, Q: integer;

  procedure Push(const L: UTF8String);
  begin
    SetLength(Acc, Length(Acc) + 1);
    Acc[High(Acc)] := L;
  end;

begin
  SetLength(Acc, 0);
  Txt := StringReplace(S, '\n', #10, [rfReplaceAll]);
  Txt := StringReplace(Txt, #13, '', [rfReplaceAll]);

  repeat
    // next paragraph
    P := Pos(#10, Txt);
    if (P > 0) then
    begin
      Para := Copy(Txt, 1, P - 1);
      Delete(Txt, 1, P);
    end
    else
      Para := Txt;

    Line := '';
    Para := Trim(Para);
    while (Para <> '') do
    begin
      Q := Pos(' ', Para);
      if (Q > 0) then
      begin
        Wd := Copy(Para, 1, Q - 1);
        Delete(Para, 1, Q);
        Para := TrimLeft(Para);
      end
      else
      begin
        Wd := Para;
        Para := '';
      end;

      if (Line = '') then
        Line := Wd
      else if (MTextW(Line + ' ' + Wd, Size, Bold) <= MaxW) then
        Line := Line + ' ' + Wd
      else
      begin
        Push(Line);
        Line := Wd;
      end;
    end;
    Push(Line);
  until (P = 0);

  Result := Acc;
end;

procedure MDialog(const Title, Msg: UTF8String; const Captions: array of UTF8String;
  Selected: integer; var Rects: array of TMRect);
const
  CW = 560;
  CP = 36;
  BTN_H = 52;
var
  Lines: TMLines;
  H, X, Y, CY, BW: single;
  I, N: integer;
  R: TMRect;
begin
  MBegin;

  // dim whatever is behind
  MFillRect(0, 0, MUI_W, MUI_H, MColor($000000), 0.6);

  Lines := MWrap(Msg, 19, false, CW - 2 * CP);
  H := CP + Length(Lines) * 28 + 28 + BTN_H + CP;
  if (Title <> '') then
    H := H + 46;

  X := (MUI_W - CW) / 2;
  Y := (MUI_H - H) / 2;
  MFillRound(X, Y, CW, H, 24, mcSurface, 1);
  MStrokeRound(X, Y, CW, H, 24, 1, mcBorder, 1);

  CY := Y + CP;
  if (Title <> '') then
  begin
    MText(X + CP, CY, Title, 26, true, mcText, 1, mtaLeft, CW - 2 * CP);
    CY := CY + 46;
  end;
  for I := 0 to High(Lines) do
  begin
    MText(X + CP, CY, Lines[I], 19, false, mcMuted, 1);
    CY := CY + 28;
  end;

  N := Length(Captions);
  if (N > 0) then
  begin
    BW := (CW - 2 * CP - (N - 1) * 12) / N;
    for I := 0 to N - 1 do
    begin
      R := MRect(X + CP + I * (BW + 12), Y + H - CP - BTN_H, BW, BTN_H);
      if (I <= High(Rects)) then
        Rects[I] := R;
      if (I = Selected) then
      begin
        MFillRound(R.X, R.Y, R.W, R.H, 14, mcAccent, 1);
        MText(R.X + R.W / 2, R.Y + 16, Captions[I], 19, true, mcOnAccent, 1, mtaCenter, R.W - 20);
      end
      else
      begin
        MFillRound(R.X, R.Y, R.W, R.H, 14, mcSurface2, 1);
        MStrokeRound(R.X, R.Y, R.W, R.H, 14, 1, mcBorder, 1);
        MText(R.X + R.W / 2, R.Y + 16, Captions[I], 19, true, mcText, 1, mtaCenter, R.W - 20);
      end;
    end;
  end;

  MEnd;
end;

function MKeyHint(X, Y: single; const Key, Caption: UTF8String): single;
var
  KW: single;
begin
  KW := MTextW(Key, 15, true);
  MFillRound(X, Y - 4, KW + 16, 26, 7, mcSurface, 1);
  MStrokeRound(X, Y - 4, KW + 16, 26, 7, 1, mcBorder, 1);
  MText(X + 8, Y, Key, 15, true, mcText, 1);
  MText(X + KW + 24, Y, Caption, 15, false, mcMuted, 1);
  Result := KW + 24 + MTextW(Caption, 15, false);
end;

{ --- icons --- }

procedure MLine(X1, Y1, X2, Y2, Thick: single; const C: TMColor; A: single);
var
  DX, DY, L, NX, NY: single;
  Tris: TTriangleList;
begin
  // a thick line as two triangles (the renderer's own lines are pixel-sized)
  DX := X2 - X1;
  DY := Y2 - Y1;
  L := Sqrt(DX * DX + DY * DY);
  if (L < 0.001) then
    Exit;
  NX := -DY / L * Thick / 2;
  NY := DX / L * Thick / 2;
  SetLength(Tris, 2);
  SetTri(Tris[0], X1 + NX, Y1 + NY, X2 + NX, Y2 + NY, X2 - NX, Y2 - NY, C, A);
  SetTri(Tris[1], X1 + NX, Y1 + NY, X2 - NX, Y2 - NY, X1 - NX, Y1 - NY, C, A);
  Renderer.DrawTriangles(Tris);
  // round caps
  MFillCircle(X1, Y1, Thick / 2, C, A);
  MFillCircle(X2, Y2, Thick / 2, C, A);
end;

procedure MIconPlay(CX, CY, Size: single; const C: TMColor; A: single);
var
  H: single;
begin
  H := Size / 2;
  Renderer.DrawTriangle(CX - H * 0.7, CY - H, CX + H, CY, CX - H * 0.7, CY + H, 0, C.R, C.G, C.B, A);
end;

procedure MIconNote(CX, CY, Size: single; const C: TMColor; A: single);
var
  S, T: single;
begin
  S := Size / 24;
  T := 2 * S;
  // two stems, a beam and two note heads
  MLine(CX - 3 * S, CY + 6 * S, CX - 3 * S, CY - 7 * S, T, C, A);
  MLine(CX + 9 * S, CY + 4 * S, CX + 9 * S, CY - 9 * S, T, C, A);
  MLine(CX - 3 * S, CY - 7 * S, CX + 9 * S, CY - 9 * S, T, C, A);
  MFillCircle(CX - 6 * S, CY + 6 * S, 3.2 * S, C, A);
  MFillCircle(CX + 6 * S, CY + 4 * S, 3.2 * S, C, A);
end;

procedure MIconBack(CX, CY, Size: single; const C: TMColor; A: single);
var
  S: single;
begin
  S := Size / 24;
  MLine(CX + 3 * S, CY - 6 * S, CX - 3 * S, CY, 2 * S, C, A);
  MLine(CX - 3 * S, CY, CX + 3 * S, CY + 6 * S, 2 * S, C, A);
end;

procedure MIconSearch(CX, CY, Size: single; const C: TMColor; A: single);
var
  S: single;
begin
  S := Size / 24;
  MStrokeRound(CX - 8 * S, CY - 8 * S, 14 * S, 14 * S, 7 * S, 2 * S, C, A);
  MLine(CX + 4 * S, CY + 4 * S, CX + 8 * S, CY + 8 * S, 2 * S, C, A);
end;

procedure MIconMic(CX, CY, Size: single; const C: TMColor; A: single);
var
  S: single;
begin
  S := Size / 24;
  MStrokeRound(CX - 3 * S, CY - 10 * S, 6 * S, 12 * S, 3 * S, 2 * S, C, A);
  MLine(CX - 7 * S, CY - 1 * S, CX - 6 * S, CY + 3 * S, 2 * S, C, A);
  MLine(CX + 7 * S, CY - 1 * S, CX + 6 * S, CY + 3 * S, 2 * S, C, A);
  MLine(CX - 6 * S, CY + 3 * S, CX, CY + 6 * S, 2 * S, C, A);
  MLine(CX + 6 * S, CY + 3 * S, CX, CY + 6 * S, 2 * S, C, A);
  MLine(CX, CY + 6 * S, CX, CY + 10 * S, 2 * S, C, A);
end;

function MApproach(Cur, Target, Speed: single): single;
var
  T: single;
begin
  T := TimeSkip * Speed;
  if (T > 1) or (T < 0) then
    T := 1;
  Result := Cur + (Target - Cur) * T;
  if Abs(Target - Result) < 0.01 then
    Result := Target;
end;

initialization
  mcBg       := MColor($0D0E12);
  mcSurface  := MColor($181A21);
  mcSurface2 := MColor($1F222B);
  mcBorder   := MColor($2A2D36);
  mcText     := MColor($F2F3F5);
  mcMuted    := MColor($A9ADB8);
  mcAccent   := MColor($D4FF4F);
  mcOnAccent := MColor($0D0E12);
  mcGood     := MColor($5BE38C);

end.
