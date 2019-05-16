unit diagramblock;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, types, DiagramTypes, Graphics, textrender,
  ComCtrls, gl, glext;

type

  TDiagramBlock=class;
  TDiagramBlockSideDescriptor=record
    block: TDiagramBlock;
    side: TDiagramBlockSide;
    sideposition: integer; //0 is center, -1 is one pixel to the left, 1 is one pixel to the rigth
  end;

  TDBCustomDrawEvent=procedure(Sender: TDiagramBlock; const ARect: TRect; beforePaint: boolean; var DefaultDraw: Boolean) of object;

  TDiagramBlock=class
  private
    fx,fy: integer;
    fwidth: integer;
    fheight: integer;

    fname: string;
    fcaption: string;

    fOnDoubleClickHeader: TNotifyEvent;
    fOnDoubleClickBody: TNotifyEvent;
    fOnRenderHeader: TDBCustomDrawEvent;
    fOnRenderBody: TDBCustomDrawEvent;

    data: TStringList;

    captionheight: integer;
    config: TDiagramConfig;
    fOnDestroy: TNotifyEvent;

    useCustomBackgroundColor: boolean;
    customBackgroundColor: tcolor;

    useCustomTextColor: boolean;
    CustomTextColor: Tcolor;

    fAutoSide: boolean;
    fAutoSideDistance: integer;

    fAutoSize: boolean;
    preferedWidth, preferedHeight: integer;

    hasChanged: boolean;
    cachedBlock: TBitmap; //Cache the block image and only update when changes happen
    ftexture: glint;

    function getBackgroundColor: TColor;
    procedure setBackgroundColor(c: TColor);
    function getTextColor: TColor;
    procedure setTextColor(c: TColor);
    function getCanvas: TCanvas;
    function getOwner: TCustomControl;
    procedure setCaption(c: string);

    procedure setWidth(w: integer);
    procedure setHeight(h: integer);

    procedure DataChange(sender: TObject);

    procedure setx(newx: integer);
    procedure sety(newy: integer);
    function getRect: trect;
    procedure setRect(r: trect);
  public

    function getData: TStrings;
    procedure setData(s: TStrings);
    procedure dblClick(xpos,ypos: integer);

    function IsAtBorder(xpos, ypos: integer; out side: TDiagramBlockSide): boolean;
    function IsInsideHeader(xpos,ypos: integer):boolean;
    function IsInsideBody(xpos,ypos: integer):boolean;
    function IsInside(xpos,ypos: integer):boolean;
    function OverlapsWith(otherBlock: TDiagramBlock): boolean;
    procedure resize(xpos, ypos: integer; side: TDiagramBlockSide);
    function getConnectPosition(side: TDiagramBlockSide; position: integer=0): tpoint;
    function getClosestSideDescriptor(xpos,ypos: integer): TDiagramBlockSideDescriptor;

    procedure setAutoSize(state: boolean);
    procedure DoAutoSize;

    procedure render;
    property OnDestroy: TNotifyEvent read fOnDestroy write fOnDestroy;
    property BlockRect: TRect read getRect write setRect;
    constructor create(graphConfig: TDiagramConfig);
    destructor destroy; override;
  published
    property Owner: TCustomControl read getOwner;
    property Canvas: TCanvas read getCanvas;
    property X: integer read fx write setX;
    property Y: integer read fy write setY;
    property Width: integer read fwidth write setWidth;
    property Height: integer read fheight write setHeight;
    property Caption: string read fcaption write setCaption;
    property Strings: TStrings read getData write setData;
    property BackgroundColor: TColor read getBackgroundColor write setBackgroundColor;
    property TextColor: TColor read getTextColor write setTextColor;
    property Name: string read fname write fname;
    property AutoSize: boolean read fAutoSize write setAutoSize;
    property AutoSide: boolean read fAutoSide write fAutoSide;
    property AutoSideDistance: integer read fAutoSideDistance write fAutoSideDistance;
    property OnDoubleClickHeader: TNotifyEvent read fOnDoubleClickHeader write fOnDoubleClickHeader;
    property OnDoubleClickBody: TNotifyEvent read fOnDoubleClickBody write fOnDoubleClickBody;
    property OnRenderHeader: TDBCustomDrawEvent read fOnRenderHeader write fOnRenderHeader;
    property OnRenderBody: TDBCustomDrawEvent read fOnRenderBody write fOnRenderBody;
  end;

implementation

uses math;

procedure TDiagramBlock.setx(newx: integer);
begin
  if newx<=-width+2 then
    newx:=-width+2;

  fx:=newx;
end;

procedure TDiagramBlock.sety(newy: integer);
begin
  if newy<=-captionheight+2 then
    newy:=-captionheight+2;

  fy:=newy;
end;

function TDiagramBlock.getBackgroundColor: TColor;
begin
  if useCustomBackgroundColor then
    result:=customBackgroundColor
  else
    result:=config.BlockBackground;
end;

procedure TDiagramBlock.setBackgroundColor(c: TColor);
begin
  customBackgroundColor:=c;
  useCustomBackgroundColor:=true;
end;

function TDiagramBlock.getTextColor: TColor;
begin
  if useCustomTextColor then
    result:=CustomTextColor
  else
    result:=config.blockTextColorNoMarkup;
end;

procedure TDiagramBlock.setTextColor(c: TColor);
begin
  CustomTextColor:=c;
  useCustomTextColor:=true;
end;

function TDiagramBlock.getOwner: TCustomControl;
begin
  result:=config.owner;
end;


function TDiagramBlock.getCanvas: TCanvas;
begin
  result:=config.canvas;
end;

procedure TDiagramBlock.setCaption(c: string);
begin
  fcaption:=c;
  hasChanged:=true;

  if fAutoSize then
    DoAutoSize;

end;

procedure TDiagramBlock.setWidth(w: integer);
begin
  fwidth:=w;
  hasChanged:=true;
end;

procedure TDiagramBlock.setHeight(h: integer);
begin
  fheight:=h;
  hasChanged:=true;
end;

procedure TDiagramBlock.DataChange(sender: TObject);
begin
  hasChanged:=true;
  if fAutoSize then
    DoAutoSize;
end;

procedure TDiagramBlock.setAutoSize(state: boolean);
begin
  fAutoSize:=state;
  if state then
  begin
    hasChanged:=true;
    DoAutoSize;
  end;
end;

procedure TDiagramBlock.DoAutoSize;
begin
  if fAutoSize=false then exit;

  render;

  width:=preferedwidth+10;
  height:=preferedheight;

end;

procedure TDiagramBlock.render;
var
  c: TCanvas;
  oldbgc: TColor;
  oldfontcolor: TColor;
  renderOriginal: boolean;

  cr,tr: TRect;

  pp: PByte;
begin
  //render the block at the given location
  //if config.canvas=nil then exit;

  if hasChanged or (config.UseOpenGL and (ftexture=0)) then
  begin
    //render
    if cachedBlock=nil then
    begin
      cachedblock:=tbitmap.Create;
      cachedblock.width:=width;
      cachedblock.height:=height;
      cachedblock.PixelFormat:=pf32bit;
    end;

    if cachedblock.width<>width then cachedblock.width:=width;
    if cachedblock.height<>height then cachedblock.height:=height;

    c:=cachedblock.Canvas;
    cachedblock.Canvas.brush.Assign(config.canvas.brush);
    cachedblock.Canvas.pen.Assign(config.canvas.pen);
    cachedblock.Canvas.font.Assign(config.canvas.font);

    oldbgc:=c.brush.color;
    c.brush.color:=BackgroundColor;

    c.FillRect(0,0,width,height);
    c.Rectangle(0,0,width,height);


    if captionheight=0 then
      captionheight:=c.GetTextHeight('XxYyJjQq')+4;

    c.Rectangle(0,0,width,captionheight);

    oldfontcolor:=c.font.color;
    c.font.color:=TextColor;

    renderOriginal:=true;
    if assigned(fOnRenderHeader) then
      fOnRenderHeader(self,rect(0,0,width-1,captionheight),true, renderOriginal);

    if renderOriginal then
    begin
      cr:=renderFormattedText(c, rect(0,0,width-1,captionheight),1,0,caption);
      if assigned(fOnRenderHeader) then
        fOnRenderHeader(self,rect(0,0,width-1,captionheight),false, renderOriginal);
    end;


    renderOriginal:=true;
    if assigned(fOnRenderBody) then
      fOnRenderBody(self,rect(0,0,width-1,captionheight),true, renderOriginal);

    if renderOriginal then
    begin
      tr:=renderFormattedText(c, rect(0,captionheight,width-1,height-2),1,captionheight,data.text);
      if assigned(fOnRenderBody) then
        fOnRenderBody(self,rect(0,0,width-1,captionheight),false, renderOriginal);
    end;


    preferedwidth:=cr.Width;
    if preferedwidth<tr.Width then preferedwidth:=tr.Width;

    preferedheight:=captionheight+tr.height;


    c.font.color:=oldfontcolor;
    c.brush.color:=oldbgc;

    haschanged:=false;

    if config.UseOpenGL and (width>0) and (height>0) then
    begin
      if ftexture=0 then
        glGenTextures(1, @ftexture);

      glBindTexture(GL_TEXTURE_2D, ftexture);
      glActiveTexture(GL_TEXTURE0);

      pp:=cachedBlock.RawImage.Data;
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, cachedBlock.Width, cachedBlock.height, 0, GL_BGRA,  GL_UNSIGNED_BYTE, pp);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    end;
  end;

  //draw the cached block
  if config.UseOpenGL then
  begin
    if ftexture=0 then
    begin
      haschanged:=true;
      exit; //should never happen
    end;

    //render a quad with this texture
    glBindTexture(GL_TEXTURE_2D, ftexture);
    glActiveTexture(GL_TEXTURE0);

    glColor3f(1,1,1);


    glScalef(config.zoom, config.zoom,1);
    glTranslatef(-config.scrollx,-config.scrolly,0);


    glBegin(GL_QUADS);              // Each set of 4 vertices form a quad

    glTexCoord2f(0,0);
    glVertex2f(x,y);

    glTexCoord2f(0,1);
    glVertex2f(x,y+height);

    glTexCoord2f(1,1);
    glVertex2f(x+width,y+height);

    glTexCoord2f(1,0);
    glVertex2f(x+width,y);

    glEnd();

    glLoadIdentity();

  end
  else
  begin
    config.canvas.StretchDraw(rect(trunc((x-config.scrollx)*config.zoom),trunc((y-config.scrolly)*config.zoom),ceil(((x-config.scrollx)+width)*config.zoom),ceil(((y-config.scrolly)+Height)*config.zoom)),cachedblock);
    //config.canvas.Draw(x-config.scrollx,y-config.scrolly,cachedBlock);
  end;
end;

function TDiagramBlock.getData: TStrings;
begin
  result:=data;
end;

procedure TDiagramBlock.setData(s: TStrings);
begin
  data.clear;
  data.Assign(s);
  hasChanged:=true;
end;

procedure TDiagramBlock.dblClick(xpos,ypos: integer);
begin
  if assigned(fOnDoubleClickBody) and IsInsideBody(xpos,ypos) then
    fOnDoubleClickBody(self)
  else
  if assigned(fOnDoubleClickHeader) and IsInsideHeader(xpos,ypos) then
    fOnDoubleClickHeader(self);

end;

function TDiagramBlock.getRect: trect;
begin
  result.Left:=x;
  result.top:=y;
  result.Right:=x+width;
  result.Bottom:=y+height;
end;

procedure TDiagramBlock.setRect(r: trect);
begin
  x:=r.left;
  y:=r.top;
  width:=r.width;
  height:=r.height;
end;

function TDiagramBlock.OverlapsWith(otherBlock: TDiagramBlock): boolean;
var r1,r2: Trect;
begin
  r1:=blockrect;
  r2:=otherblock.blockrect;
  result:=r1.IntersectsWith(r2);
end;

function TDiagramBlock.IsInsideHeader(xpos,ypos: integer):boolean;
var
  headerrect: trect;
begin
  headerrect:=rect(x,y,x+width,y+captionheight);
  result:=PtInRect(headerrect,point(xpos,ypos));
end;

function TDiagramBlock.IsInsideBody(xpos,ypos: integer):boolean;
var
  bodyrect: trect;
begin
  bodyrect:=rect(x,y+captionheight,x+width,y+height);
  result:=PtInRect(bodyrect,point(xpos,ypos));
end;

function TDiagramBlock.IsInside(xpos,ypos: integer):boolean;
var
  r: trect;
begin
  r:=rect(x,y,x+width,y+height);
  result:=PtInRect(r,point(xpos,ypos));
end;

function TDiagramBlock.IsAtBorder(xpos, ypos: integer; out side: TDiagramBlockSide): boolean;
var
  borderthickness: integer;
begin
  result:=false;
  borderthickness:=3;

  if PtInRect(rect(x-borderthickness,y-borderthickness,x+width+borderthickness,y+height+borderthickness),point(xpos,ypos))=false then exit; //not even within the range

  //still here so it's within the region
  if PtInRect(rect(x-borderthickness,y-borderthickness, x+borderthickness,y+borderthickness),point(xpos,ypos)) then
  begin
    side:=dbsTopLeft;
    exit(true);
  end;

  if PtInRect(rect(x+width-borderthickness,y-borderthickness, x+width+borderthickness,y+borderthickness),point(xpos,ypos)) then
  begin
    side:=dbsTopRight;
    exit(true);
  end;

  if PtInRect(rect(x-borderthickness,y+height-borderthickness, x+borderthickness,y+height+borderthickness),point(xpos,ypos)) then
  begin
    side:=dbsBottomLeft;
    exit(true);
  end;

  if PtInRect(rect(x+width-borderthickness,y+height-borderthickness, x+width+borderthickness,y+height+borderthickness),point(xpos,ypos)) then
  begin
    side:=dbsBottomRight;
    exit(true);
  end;

  if PtInRect(rect(x,y-borderthickness, x+width,y+borderthickness),point(xpos,ypos)) then
  begin
    side:=dbsTop;
    exit(true);
  end;

  if PtInRect(rect(x+width-borderthickness,y, x+width+borderthickness,y+height),point(xpos,ypos)) then
  begin
    side:=dbsRight;
    exit(true);
  end;

  if PtInRect(rect(x,y+height-borderthickness, x+width,y+height+borderthickness),point(xpos,ypos)) then
  begin
    side:=dbsBottom;
    exit(true);
  end;

  if PtInRect(rect(x-borderthickness,y, x+borderthickness,y+height),point(xpos,ypos)) then
  begin
    side:=dbsLeft;
    exit(true);
  end;
end;

function TDiagramBlock.getClosestSideDescriptor(xpos,ypos: integer): TDiagramBlockSideDescriptor;
var
  r: TDiagramBlockSideDescriptor;

  cx,cy: integer;

  p: tpoint;
  closestpointdistance: ValReal;
  distance: ValReal;
begin
  r.block:=self;
  r.sideposition:=0;
  cx:=x+width div 2;
  cy:=y+height div 2;

  //calculate the side and position closest to the given x/ypos

  if ypos<y then
  begin
    //top
    if xpos<x then
    begin
      //topleft
      r.side:=dbsTopLeft;
    end
    else
    if xpos>x+width then
    begin
      //topright
      r.side:=dbsTopRight;
    end
    else
    begin
      //top
      r.side:=dbsTop;
      r.sideposition:=xpos-cx;
    end;
  end
  else
  if ypos>y+height then
  begin
    //bottom
    if xpos<x then
    begin
      //bottomleft
      r.side:=dbsBottomLeft;
    end
    else
    if xpos>x+width then
    begin
      //bottomright
      r.side:=dbsBottomRight;
    end
    else
    begin
      //bottom
      r.side:=dbsBottom;
      r.sideposition:=xpos-cx;
    end;
  end
  else
  begin
    //left/right
    if xpos<x then
    begin
      //left
      r.side:=dbsLeft;
      r.sideposition:=ypos-cy;
    end
    else
    if xpos>x+width then
    begin
      //right
      r.side:=dbsRight;
      r.sideposition:=ypos-cy;
    end
    else
    begin
      //inside
      //calculate which side is closest
      //top
      p:=point(xpos,ypos);
      closestpointdistance:=point(xpos,y).Distance(p);
      r.side:=dbsTop;
      r.sideposition:=xpos-cx;


      //topright
      distance:=point(x+width,y).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsTopRight;
        r.sideposition:=0;
      end;

      //right
      distance:=point(x+width,ypos).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsRight;
        r.sideposition:=ypos-cy;
      end;

      //bottomright
      distance:=point(x+width,y+height).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsBottomRight;
        r.sideposition:=0;
      end;

      //bottom
      distance:=point(xpos,y+height).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsBottom;
        r.sideposition:=xpos-cx;
      end;

      //bottomleft
      distance:=point(x,y+height).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsBottomRight;
        r.sideposition:=0;
      end;

      //left
      distance:=point(x,ypos).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsLeft;
        r.sideposition:=ypos-cy;
      end;

      //topleft
      distance:=point(x,y).Distance(p);
      if distance<closestpointdistance then
      begin
        closestpointdistance:=distance;
        r.side:=dbsTopLeft;
        r.sideposition:=0;
      end;
    end;
  end;

  result:=r;
end;

function TDiagramBlock.getConnectPosition(side: TDiagramBlockSide; position: integer=0): tpoint;
//returns the canvas x,y position of the specified side's center, offset by the given position up to the max length of the side
var
  hc,vc: integer;
begin
  case side of
    dbsTopLeft: exit(point(x,y));
    dbsTop:
    begin
      hc:=width div 2;
      if (abs(position)>hc) then
      begin
        if position>0 then position:=hc else position:=-hc;
      end;

      exit(point(x+hc+position,y));
    end;

    dbsTopRight: exit(point(x+width,y));

    dbsRight:
    begin
      vc:=height div 2;
      if (abs(position)>vc) then
      begin
        if position>0 then position:=vc else position:=-vc;
      end;
      exit(point(x+width,y+vc+position));
    end;

    dbsBottomRight: exit(point(x+width,y+height));

    dbsBottom:
    begin
      hc:=width div 2;
      if (abs(position)>hc) then
      begin
        if position>0 then position:=hc else position:=-hc;
      end;

      exit(point(x+hc+position,y+height));
    end;

    dbsBottomLeft: exit(point(x,y+height));

    dbsLeft:
    begin
      vc:=height div 2;
      if (abs(position)>vc) then
      begin
        if position>0 then position:=vc else position:=-vc;
      end;
      exit(point(x,y+vc+position));
    end;
  end;
end;

procedure TDiagramBlock.resize(xpos, ypos: integer; side: TDiagramBlockSide);
var d: integer;
  procedure resizeLeft;
  begin
    if xpos>=(x+width-1) then xpos:=x+width-1;
    d:=xpos-x;
    width:=width-d;
    x:=xpos;
  end;

  procedure resizeTop;
  begin
    if ypos>=(y+height-captionheight-1) then ypos:=y+height-captionheight-1;
    d:=ypos-y;
    height:=height-d;
    y:=ypos;
  end;

  procedure resizeRight;
  begin
    width:=xpos-x;
    if width<1 then width:=1;
  end;

  procedure resizeBottom;
  begin
    height:=ypos-y;
    if height<captionheight then height:=captionheight;
  end;

begin
  case side of
    dbsTopLeft:
    begin
      resizeLeft;
      resizeTop;
    end;

    dbsTop: resizeTop;
    dbsTopRight:
    begin
      resizeTop;
      resizeRight;
    end;

    dbsRight: resizeRight;
    dbsBottomRight:
    begin
      resizeBottom;
      resizeRight;
    end;

    dbsBottom: resizeBottom;
    dbsBottomLeft:
    begin
      resizeBottom;
      resizeLeft;
    end;

    dbsLeft: resizeLeft;
  end;

end;

constructor TDiagramBlock.create(graphConfig: TDiagramConfig);
begin
  data:=TStringList.create;
  data.OnChange:=@DataChange;

  config:=GraphConfig;
  x:=0;
  y:=0;
  width:=100;
  height:=100;

end;

destructor TDiagramBlock.destroy;
begin
  if assigned(OnDestroy) then
    OnDestroy(self);

  //owner.NotifyBlockDestroy(self);

  data.free;

  if cachedblock<>nil then
    freeandnil(cachedblock);

  inherited destroy;
end;



end.

