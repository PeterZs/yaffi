unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  strutils;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    CheckBox1: TCheckBox;
    CheckBox2: TCheckBox;
    Memo1: TMemo;
    OpenDialog1: TOpenDialog;
    function ByteArrayToString(const ByteArray: array of Byte): AnsiString;
    procedure Button1Click(Sender: TObject);
    Function PosCaseInsensitive(const AText, ASubText: string): Integer;
    function IndexOfDWord(const buf: pointer; len:SizeInt; b:DWord {or QWord }):SizeInt;
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

function TForm1.ByteArrayToString(const ByteArray: array of Byte): AnsiString;
//http://stackoverflow.com/questions/19677946/converting-string-to-byte-array-wont-work
var
  I: Integer;
begin
  SetLength(Result, SizeOf(ByteArray));
  for I := 1 to SizeOf(ByteArray) do
    Result[I] := Chr(ByteArray[I - 1]);
end;

// IndexOfDWord is a customised version of IndexDWord, supplied to me by my friend Engkin
// and more optimised for rapid buffer search of 4 or 8 byte values
function TForm1.IndexOfDWord(const buf: pointer; len:SizeInt; b:DWord {or QWord }):SizeInt;
var
  p,e:PDWord;
  pb: PByte absolute p;
begin
  Result := -1;
  p := PDWord(buf);
  e := PDWord(PtrUInt(buf) + len - 1 - SizeOf(DWord) {4 for DWord / 8 for QWord} );
  while (p <= e) do
  begin
    if (p^=b) then
      exit(PtrUInt(p)-PtrUInt(buf));
    inc(pb);
  end;
end;

// A bespoke version of Hex2Dec, which can't return values larger than DWORD (4 bytes)
// Hex2DecBig allows up to QWORD (twice as large as Int64), but the realistic
// max size is that of Int64 due to use of Val within StrToQword, i.e.
// 7fffffffffffffff : 9,223,372,036,854,775,807
function Hex2DecBig(const S: string): QWORD;
var
  HexStr: string;
begin
  if Pos('$',S)=0 then
    HexStr:='$'+ S
  else
    HexStr:=S;
  Result:=StrToQWord(HexStr);
end;

// Pos uses AnsiPos internally so bespoke version of Pos this is
// and used for finding search results when the user asks for no case sensitivity
Function TForm1.PosCaseInsensitive(const AText, ASubText: string): Integer;
var
  s1, s2 : ansistring;
begin
  s1 := AnsiUppercase(ASubText);
  s2 :=    AnsiUppercase(AText);
  Result := AnsiPos(s2, s1);
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  fs : TFileStream;
  TotalBytesRead, PositionFoundOnDisk, HexVal : Int64;
  BytesRead : LongInt;
  HexValAsDec : QWord;
  i, PositionFoundInBuffer : integer;
  PosInBufferOfHexValue : SizeInt;
  BufferA : array [0..32767] of byte; // the binary buffer read from disk
  SearchHitLocation : PChar;
  TextData : ansistring;
  CaseSensitive, HexSearch : Boolean;

begin
  i := 0;
  BytesRead := 0;
  TotalBytesRead := 0;
  PositionFoundInBuffer := 0;
  PositionFoundOnDisk := 0;
  HexVal := 0;
  HexValAsDec := 0;
  CaseSensitive := false;
  HexSearch := false;

  if CheckBox1.Checked then CaseSensitive := true else CaseSensitive := false;
  if CheckBox2.Checked then HexSearch := true else HexSearch := false;

  OpenDialog1.Execute;
  fs := TFileStream.Create(OpenDialog1.FileName, fmOpenRead);
  fs.Position := 0;

  //FillChar(BufferA,SizeOf(BufferA),0);
  while TotalBytesRead < fs.Size do
  repeat
    // Read the raw file
    BytesRead := fs.Read(BufferA, SizeOf(BufferA));
    if BytesRead = -1 then
      RaiseLastOSError
    else inc(TotalBytesRead, BytesRead);

    // Convert byte array to string
    TextData := ByteArrayToString(BufferA);
    // Do ANSI and Unicode search (Pos will deal with both)
    if CaseSensitive = true then
      // Do a case SENSITIVE search.
      begin
        for i := 0 to Memo1.Lines.Count -1 do
          begin
            if Pos(Trim(Memo1.Lines[i]), TextData) > 0 then
              begin
                PositionFoundInBuffer := Pos(Memo1.Lines[i], TextData);
                PositionFoundOnDisk := (TotalBytesRead - BytesRead) + (PositionFoundInBuffer -1);
                ShowMessage('found ' + Memo1.Lines[i] + ' at offset ' + IntToStr(PositionFoundOnDisk));
              end;
          end;
      end
    else if (CaseSensitive = false and HexSearch = false) then
    begin
      // Do a case INSENSITIVE search.
      for i := 0 to Memo1.Lines.Count -1 do
        begin
          if PosCaseInsensitive(Trim(Memo1.Lines[i]), TextData) > 0 then
              begin
                PositionFoundInBuffer := Pos(Memo1.Lines[i], TextData);
                PositionFoundOnDisk := (TotalBytesRead - BytesRead) + (PositionFoundInBuffer -1);
                ShowMessage('found ' + Memo1.Lines[i] + ' at offset ' + IntToStr(PositionFoundOnDisk));
              end;
        end;
    end
    else if HexSearch = true then
      begin
        for i := 0 to Memo1.Lines.Count -1 do
          begin
            // Take each hex string and convert to decimal
            // Up to 8 bytes allowed, but must not exceed 7fffffffffffffff
            // (the Int64 max of 9,223,372,036,854,775,807)
            HexValAsDec := Hex2DecBig(DelSpace(Memo1.Lines[i]));
            // Search for the integer representation using bespoke, fast, IndexOfDWord function
            PosInBufferOfHexValue := IndexOfDWord(@BufferA[0], Length(BufferA), SwapEndian(HexValAsDec)); //SwapEndian($4003E369)); //StrToInt('$' + Memo1.Lines[i]));
            PositionFoundOnDisk := (TotalBytesRead - BytesRead) + PosInBufferOfHexValue;
            ShowMessage(IntToStr(PositionFoundOnDisk));
          end;
      end;
  until TotalBytesRead = fs.size;
  ShowMessage(IntToStr(TotalBytesRead) + ' read. Done');
  fs.Free;
end;

end.

