{
  URemoteQueue - the game's side of the phone song queue (ui-v2).

  A small web server (remote/karaoke_remote.py) lets guests on the same
  network queue songs from their phones. The two sides only share plain
  text files in <game user dir>/remote:

    written here                      written by the server
    ------------                      ---------------------
    songs.tsv       the song list     queue.txt  qid<TAB>key<TAB>title<TAB>artist
    nowplaying.txt  what's on now     url.txt    address to show on the TV
    claims/<qid>    "started this"    qr.txt     QR code of that address (0/1 rows)

  A song's key is its full .txt path, so it survives restarts.
}
unit URemoteQueue;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  USong;

type
  TRemoteItem = record
    QID:    UTF8String;
    Key:    UTF8String;
    Title:  UTF8String;
    Artist: UTF8String;
  end;

// re-reads the shared files (at most once a second; cheap to call every frame)
procedure RemotePoll;

// songs waiting, in order (already started ones are left out)
function RemoteQueueCount: integer;
function RemoteQueueItem(Index: integer): TRemoteItem;

// address guests open, and its QR code ('' / size 0 while the server is off)
function RemoteURL: UTF8String;
function RemoteQRSize: integer;
function RemoteQRDark(X, Y: integer): boolean;

// writes songs.tsv for the server (skipped when nothing changed)
procedure RemoteExportSongs;

// tells the server what's being sung; Song = nil when nothing is
procedure RemoteNowPlaying(Song: TSong; Elapsed, Duration: real);

// true when the next queued song can be started right now
function RemoteCanStart: boolean;

// starts the next queued song (fades to the singing screen)
function RemoteStartNext: boolean;

implementation

uses
  Classes,
  SysUtils,
  sdl2,
  UDisplay,
  UGraphic,
  UNote,
  UPath,
  UPlatform,
  UScreenSong,
  USongs;

var
  Queue:       array of TRemoteItem;
  Claimed:     TStringList = nil;   // qids we started this session
  QR:          TStringList = nil;
  URL:         UTF8String = '';
  LastPoll:    cardinal = 0;
  LastAddr:    cardinal = 0;
  ExportCount: integer = -1;
  NowKey:      UTF8String = '';
  NowHasDur:   boolean = false;
  KeyIndex:    TStringList = nil;   // song key -> CatSongs index
  KeyCount:    integer = -1;

function RemoteDir: UTF8String;
begin
  Result := IncludeTrailingPathDelimiter(Platform.GetGameUserPath.Append('remote').ToNative);
end;

function SongKey(Song: TSong): UTF8String;
begin
  Result := Song.Path.Append(Song.FileName).ToNative;
end;

function Clean(const S: UTF8String): UTF8String;
begin
  Result := StringReplace(S, #9, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

procedure SaveAtomic(List: TStringList; const FileName: UTF8String);
begin
  try
    ForceDirectories(RemoteDir);
    List.SaveToFile(FileName + '.tmp');
    if FileExists(FileName) then
      DeleteFile(FileName);
    RenameFile(FileName + '.tmp', FileName);
  except
    // the queue is a bonus; never let it stop the game
  end;
end;

procedure EnsureLists;
begin
  if (Claimed = nil) then
  begin
    Claimed := TStringList.Create;
    Claimed.Sorted := true;
    Claimed.Duplicates := dupIgnore;
  end;
  if (QR = nil) then
    QR := TStringList.Create;
end;

// splits one queue line on tabs (no quoting, unlike TStringList)
function SplitLine(const Line: UTF8String; out Item: TRemoteItem): boolean;
var
  Fields: array[0..3] of UTF8String;
  I, N, Start: integer;
begin
  N := 0;
  Start := 1;
  for I := 1 to Length(Line) + 1 do
    if (I > Length(Line)) or (Line[I] = #9) then
    begin
      if (N <= 3) then
        Fields[N] := Copy(Line, Start, I - Start);
      Inc(N);
      Start := I + 1;
    end;
  Result := (N >= 4) and (Fields[0] <> '');
  if Result then
  begin
    Item.QID := Fields[0];
    Item.Key := Fields[1];
    Item.Title := Fields[2];
    Item.Artist := Fields[3];
  end;
end;

procedure ReadQueue;
var
  L: TStringList;
  I: integer;
  FileName: UTF8String;
  Item: TRemoteItem;
begin
  // the file is tiny, so just read it again (FileAge is only 2 s precise)
  FileName := RemoteDir + 'queue.txt';
  SetLength(Queue, 0);
  if not FileExists(FileName) then
    Exit;

  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
      if SplitLine(L[I], Item) then
      begin
        SetLength(Queue, Length(Queue) + 1);
        Queue[High(Queue)] := Item;
      end;
  finally
    L.Free;
  end;
end;

procedure ReadAddress;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    URL := '';
    QR.Clear;
    try
      if FileExists(RemoteDir + 'url.txt') then
      begin
        L.LoadFromFile(RemoteDir + 'url.txt');
        if (L.Count > 0) then
          URL := Trim(L[0]);
      end;
      if (URL <> '') and FileExists(RemoteDir + 'qr.txt') then
        QR.LoadFromFile(RemoteDir + 'qr.txt');
    except
      URL := '';
      QR.Clear;
    end;
    // drop a half-written code
    if (QR.Count > 0) and (Length(QR[0]) <> QR.Count) then
      QR.Clear;
  finally
    L.Free;
  end;
end;

procedure RemotePoll;
var
  Tick: cardinal;
begin
  EnsureLists;
  Tick := SDL_GetTicks();
  if (LastPoll <> 0) and (Tick - LastPoll < 1000) then
    Exit;
  LastPoll := Tick;
  ReadQueue;
  if (LastAddr = 0) or (Tick - LastAddr > 10000) then
  begin
    LastAddr := Tick;
    ReadAddress;
  end;
end;

function Waiting(Index: integer): boolean;
begin
  Result := (Claimed = nil) or (Claimed.IndexOf(Queue[Index].QID) < 0);
end;

function RemoteQueueCount: integer;
var
  I: integer;
begin
  Result := 0;
  for I := 0 to High(Queue) do
    if Waiting(I) then
      Inc(Result);
end;

function RemoteQueueItem(Index: integer): TRemoteItem;
var
  I, N: integer;
begin
  N := 0;
  for I := 0 to High(Queue) do
    if Waiting(I) then
    begin
      if (N = Index) then
      begin
        Result := Queue[I];
        Exit;
      end;
      Inc(N);
    end;
  Result.QID := '';
  Result.Key := '';
  Result.Title := '';
  Result.Artist := '';
end;

function RemoteURL: UTF8String;
begin
  Result := URL;
end;

function RemoteQRSize: integer;
begin
  if (QR = nil) then
    Result := 0
  else
    Result := QR.Count;
end;

function RemoteQRDark(X, Y: integer): boolean;
begin
  Result := (QR <> nil) and (Y >= 0) and (Y < QR.Count) and (X >= 0) and
            (X < Length(QR[Y])) and (QR[Y][X + 1] = '1');
end;

procedure RemoteExportSongs;
var
  L: TStringList;
  I, Count: integer;
  S: TSong;
  Cover: UTF8String;
  Duet: char;
begin
  if (CatSongs = nil) then
    Exit;
  Count := Length(CatSongs.Song);
  if (Count = ExportCount) then
    Exit;
  L := TStringList.Create;
  try
    try
      for I := 0 to High(CatSongs.Song) do
      begin
        S := CatSongs.Song[I];
        if S.Main then
          Continue;
        Cover := '';
        if S.Cover.IsSet then
          Cover := S.Path.Append(S.Cover).ToNative;
        if S.isDuet then
          Duet := '1'
        else
          Duet := '0';
        L.Add(Clean(SongKey(S)) + #9 + Clean(S.Title) + #9 + Clean(S.Artist) + #9 +
              IntToStr(S.Year) + #9 + Duet + #9 + Clean(Cover));
      end;
      SaveAtomic(L, RemoteDir + 'songs.tsv');
      ExportCount := Count;
    except
    end;
  finally
    L.Free;
  end;
end;

procedure RemoteNowPlaying(Song: TSong; Elapsed, Duration: real);
var
  L: TStringList;
  Key: UTF8String;
begin
  if (Song = nil) then
    Key := ''
  else
    Key := SongKey(Song);
  // write when the song changes, and once more when its length is known
  if (Key = NowKey) and ((Key = '') or NowHasDur or (Duration <= 0)) then
    Exit;
  NowKey := Key;
  NowHasDur := Duration > 0;

  L := TStringList.Create;
  try
    if (Song = nil) then
      L.Add('state=idle')
    else
    begin
      // the server takes the start time from this file's modification time
      L.Add('state=playing');
      L.Add('key=' + Clean(Key));
      L.Add('title=' + Clean(Song.Title));
      L.Add('artist=' + Clean(Song.Artist));
      L.Add('elapsed=' + IntToStr(Round(Elapsed)));
      L.Add('duration=' + IntToStr(Round(Duration)));
    end;
    SaveAtomic(L, RemoteDir + 'nowplaying.txt');
  finally
    L.Free;
  end;
end;

procedure Claim(const QID: UTF8String);
var
  F: TFileStream;
begin
  EnsureLists;
  Claimed.Add(QID);
  try
    ForceDirectories(RemoteDir + 'claims');
    F := TFileStream.Create(RemoteDir + 'claims' + PathDelim + QID, fmCreate);
    F.Free;
  except
  end;
end;

procedure BuildKeyIndex;
var
  J: integer;
begin
  if (KeyIndex <> nil) and (KeyCount = Length(CatSongs.Song)) then
    Exit;
  if (KeyIndex = nil) then
  begin
    KeyIndex := TStringList.Create;
    KeyIndex.Sorted := true;
    KeyIndex.Duplicates := dupIgnore;
    KeyIndex.CaseSensitive := true;
  end;
  KeyIndex.Clear;
  for J := 0 to High(CatSongs.Song) do
    if not CatSongs.Song[J].Main then
      KeyIndex.AddObject(SongKey(CatSongs.Song[J]), TObject(PtrInt(J)));
  KeyCount := Length(CatSongs.Song);
end;

// first waiting item that maps to a song we have; unknown songs are dropped
function NextSong(out SongIndex: integer): boolean;
var
  I, K: integer;
begin
  Result := false;
  SongIndex := -1;
  BuildKeyIndex;
  for I := 0 to High(Queue) do
  begin
    if not Waiting(I) then
      Continue;
    if KeyIndex.Find(Queue[I].Key, K) then
    begin
      SongIndex := integer(PtrInt(KeyIndex.Objects[K]));
      Result := (SongIndex >= 0) and (SongIndex <= High(CatSongs.Song));
      if Result then
        Exit;
    end;
    Claim(Queue[I].QID);   // song no longer here: take it off the queue
  end;
end;

function RemoteCanStart: boolean;
var
  Idx: integer;
begin
  Result := (CatSongs <> nil) and (RemoteQueueCount > 0) and (PlayersPlay >= 1) and
            (Length(Player) >= PlayersPlay) and (ScreenSong <> nil) and
            (ScreenSong.Mode = smNormal) and NextSong(Idx);
end;

function RemoteStartNext: boolean;
var
  I, Idx: integer;
begin
  Result := false;
  if not RemoteCanStart or not NextSong(Idx) then
    Exit;
  for I := 0 to High(Queue) do
    if Waiting(I) then
    begin
      Claim(Queue[I].QID);
      Break;
    end;

  ScreenSong.StopMusicPreview;
  ScreenSong.StopVideoPreview;
  ScreenSong.Mode := smNormal;
  CatSongs.Selected := Idx;
  Display.FadeTo(@ScreenSing);
  Result := true;
end;

finalization
  Claimed.Free;
  QR.Free;
  KeyIndex.Free;
end.
