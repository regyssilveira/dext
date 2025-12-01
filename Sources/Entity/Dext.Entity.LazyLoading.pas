unit Dext.Entity.LazyLoading;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Rtti,
  System.SysUtils,
  Dext.Entity.Core,
  Dext.Entity.Attributes;

type
  TLazyLoader = class
  private
    FContext: IDbContext;
    FEntity: TObject;
    FInterceptor: TVirtualMethodInterceptor;
    FLoadedProperties: TDictionary<string, Boolean>;
    
    procedure OnBefore(Instance: TObject; Method: TRttiMethod; const Args: TArray<TValue>; out DoInvoke: Boolean; out Result: TValue);
    function CheckNavProp(const AMethodName: string; out APropName: string; out IsCollection: Boolean): Boolean;
  public
    constructor Create(AContext: IDbContext; AEntity: TObject);
    destructor Destroy; override;
  end;

implementation

{ TLazyLoader }

constructor TLazyLoader.Create(AContext: IDbContext; AEntity: TObject);
begin
  inherited Create;
  FContext := AContext;
  FEntity := AEntity;
  FLoadedProperties := TDictionary<string, Boolean>.Create;

  FInterceptor := TVirtualMethodInterceptor.Create(FEntity.ClassType);
  FInterceptor.OnBefore := OnBefore;
  FInterceptor.Proxify(FEntity);
end;

destructor TLazyLoader.Destroy;
begin
  FInterceptor.Free;
  FLoadedProperties.Free;
  inherited;
end;

function TLazyLoader.CheckNavProp(const AMethodName: string; out APropName: string; out IsCollection: Boolean): Boolean;
var
  Ctx: TRttiContext;
  Typ: TRttiType;
  Prop: TRttiProperty;
  Props: TArray<TRttiProperty>;
  i: Integer;
  T: TRttiType;
  Attr: TCustomAttribute;
  Attrs: TArray<TCustomAttribute>;
  j: Integer;
begin
  Result := False;
  IsCollection := False;
  
  Ctx := TRttiContext.Create;
  Typ := Ctx.GetType(FEntity.ClassType);
  Props := Typ.GetProperties;
  
  for i := 0 to Length(Props) - 1 do
  begin
    Prop := Props[i];
    
    // Fallback: Assume getter is Get<PropName>
    if 'Get' + Prop.Name = AMethodName then
    begin
        Attrs := Prop.GetAttributes;
        for j := 0 to Length(Attrs) - 1 do
        begin
          Attr := Attrs[j];
          if Attr is ForeignKeyAttribute then
          begin
            APropName := Prop.Name;
            IsCollection := False;
            Exit(True);
          end;
        end;
        
        T := Prop.PropertyType;
        if T <> nil then
        begin
            if Pos('TList<', T.Name) = 1 then
            begin
                APropName := Prop.Name;
                IsCollection := True;
                Exit(True);
            end;
        end;
    end;
  end;
end;

procedure TLazyLoader.OnBefore(Instance: TObject; Method: TRttiMethod; const Args: TArray<TValue>; out DoInvoke: Boolean; out Result: TValue);
var
  PropName: string;
  IsCollection: Boolean;
  MName: string;
begin
  DoInvoke := True;
  MName := Method.Name;
  if Pos('Get', MName) <> 1 then
  begin
    Exit;
  end;
  
  if CheckNavProp(MName, PropName, IsCollection) then
  begin
    if not FLoadedProperties.ContainsKey(PropName) then
    begin
      try
        FLoadedProperties.Add(PropName, True);
        
        if IsCollection then
          FContext.Entry(FEntity).Collection(PropName).Load
        else
          FContext.Entry(FEntity).Reference(PropName).Load;
          
      except
        on E: Exception do
        begin
          raise;
        end;
      end;
    end;
  end;
end;

end.
