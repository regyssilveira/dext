unit Dext.Entity.DbSet;

interface

uses
  System.Generics.Collections,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  Dext.Core.Activator,
  Dext.Core.ValueConverters,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.Interfaces,
  Dext.Specifications.Interfaces,
  Dext.Specifications.SQL.Generator;

type
  TDbSet<T: class> = class(TInterfacedObject, IDbSet<T>, IDbSet)
  private
    FContext: IDbContext;
    FRttiContext: TRttiContext; // Keep RTTI context alive
    FTableName: string;
    FPKName: string;
    FProps: TDictionary<string, TRttiProperty>; // Column Name -> Property
    FColumns: TDictionary<string, string>;      // Property Name -> Column Name
    FIdentityMap: TObjectDictionary<string, T>; // ID (String) -> Entity. Owns objects.
    
    procedure MapEntity;
    function GetTableName: string;
    function GetPKColumn: string;
    function Hydrate(Reader: IDbReader): T;
    function GetRelatedId(const AObject: TObject): TValue;
  protected
    function GetEntityId(const AEntity: T): string;
  public
    constructor Create(AContext: IDbContext);
    destructor Destroy; override;
    
    function FindObject(const AId: Variant): TObject;
    function GenerateCreateTableScript: string;
    
    procedure Add(const AEntity: T);
    procedure Update(const AEntity: T);
    procedure Remove(const AEntity: T);
    function Find(const AId: Variant): T;
    
    function List(const ASpec: ISpecification<T>): TList<T>; overload;
    function List: TList<T>; overload;
    function FirstOrDefault(const ASpec: ISpecification<T>): T;
    
    function Any(const ASpec: ISpecification<T>): Boolean;
    function Count(const ASpec: ISpecification<T>): Integer;
  end;

implementation

{ TDbSet<T> }

constructor TDbSet<T>.Create(AContext: IDbContext);
begin
  inherited Create;
  FContext := AContext;
  FProps := TDictionary<string, TRttiProperty>.Create;
  FColumns := TDictionary<string, string>.Create;
  FIdentityMap := TObjectDictionary<string, T>.Create([doOwnsValues]);
  MapEntity;
end;

destructor TDbSet<T>.Destroy;
begin
  FIdentityMap.Free;
  FProps.Free;
  FColumns.Free;
  inherited;
end;

procedure TDbSet<T>.MapEntity;
var
  Typ: TRttiType;
  Attr: TCustomAttribute;
  Prop: TRttiProperty;
  ColName: string;
begin
  FRttiContext := TRttiContext.Create;
  Typ := FRttiContext.GetType(T);
  
  // 1. Table Name
  FTableName := Typ.Name; // Default
  for Attr in Typ.GetAttributes do
    if Attr is TableAttribute then
      FTableName := TableAttribute(Attr).Name;
      
  // 2. Properties & Columns
  for Prop in Typ.GetProperties do
  begin
    // Skip unmapped
    var IsMapped := True;
    for Attr in Prop.GetAttributes do
      if Attr is NotMappedAttribute then
        IsMapped := False;
        
    if not IsMapped then Continue;
    
    ColName := Prop.Name; // Default
    
    for Attr in Prop.GetAttributes do
    begin
      if Attr is ColumnAttribute then
        ColName := ColumnAttribute(Attr).Name;
        
      if Attr is PKAttribute then
        FPKName := ColName;
        
      // Handle ForeignKey - we map it to the column name it refers to
      // But wait, the property itself is the Entity, not the ID.
      // So we need to know the Column Name that holds the ID.
      if Attr is ForeignKeyAttribute then
      begin
        // This property is a relationship.
        // We store it in FProps with the FK Column Name so Hydrate can find it?
        // No, Hydrate iterates columns from DB.
        // If DB has 'AddressId', we need to map 'AddressId' -> Prop 'Address'.
        ColName := ForeignKeyAttribute(Attr).ColumnName;
      end;
    end;
    
    FProps.Add(ColName.ToLower, Prop); // Store lower for case-insensitive matching
    FColumns.Add(Prop.Name, ColName);
  end;
  
  if FPKName = '' then
    FPKName := 'Id'; // Convention
end;

function TDbSet<T>.GetTableName: string;
begin
  Result := FContext.Dialect.QuoteIdentifier(FTableName);
end;

function TDbSet<T>.GetPKColumn: string;
begin
  Result := FContext.Dialect.QuoteIdentifier(FPKName);
end;

function TDbSet<T>.GetEntityId(const AEntity: T): string;
var
  Prop: TRttiProperty;
  Val: TValue;
begin
  if not FProps.TryGetValue(FPKName.ToLower, Prop) then
    raise Exception.Create('Primary Key property not found.');
  Val := Prop.GetValue(Pointer(AEntity));
  Result := Val.ToString;
end;

function TDbSet<T>.GetRelatedId(const AObject: TObject): TValue;
var
  Ctx: TRttiContext;
  Typ: TRttiType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
begin
  // We need to find the PK of the related object.
  // We don't have its DbSet handy easily without looking it up, 
  // but we can just scan its properties for [PK] or 'Id'.
  
  Ctx := TRttiContext.Create;
  Typ := Ctx.GetType(AObject.ClassType);
  
  for Prop in Typ.GetProperties do
  begin
    for Attr in Prop.GetAttributes do
      if Attr is PKAttribute then
        Exit(Prop.GetValue(AObject));
  end;
  
  // Fallback to 'Id'
  Prop := Typ.GetProperty('Id');
  if Prop <> nil then
    Exit(Prop.GetValue(AObject));
    
  raise Exception.Create('Could not determine Primary Key for related entity ' + AObject.ClassName);
end;

function TDbSet<T>.Hydrate(Reader: IDbReader): T;
var
  i: Integer;
  ColName: string;
  Val: TValue;
  Prop: TRttiProperty;
  FKAttr: ForeignKeyAttribute;
  RelatedEntity: TObject;
  RelatedSet: IDbSet;
  PKVal: string;
//  PKColIndex: Integer;
begin
  // 1. Find PK Value first to check Identity Map
  PKVal := '';
  //PKColIndex := -1;
  
  // We need to find which column index corresponds to PK
  // This is a bit slow if we iterate every time. 
  // Optimization: Cache PK Column Index? But Reader column order might change.
  // Let's iterate.
  for i := 0 to Reader.GetColumnCount - 1 do
  begin
    ColName := Reader.GetColumnName(i);
    if SameText(ColName, FPKName) then
    begin
      PKVal := Reader.GetValue(i).ToString;
      // PKColIndex := i;
      Break;
    end;
  end;
  
  if (PKVal <> '') and FIdentityMap.TryGetValue(PKVal, Result) then
  begin
    // Found in cache! Return it.
    // TODO: Should we refresh properties? For now, Identity Map pattern usually means "return cached instance".
    Exit;
  end;

  // Not found, create new
  // Use Activator to create instance (handles generic constraint issue)
  Result := TActivator.CreateInstance<T>([]);
  
  // Add to Identity Map immediately if we have a PK
  if PKVal <> '' then
    FIdentityMap.Add(PKVal, Result);

  try
    for i := 0 to Reader.GetColumnCount - 1 do
    begin
      ColName := Reader.GetColumnName(i).ToLower;
      Val := Reader.GetValue(i);
      
      if FProps.TryGetValue(ColName, Prop) then
      begin
        if not Val.IsEmpty then
        begin
          // Check if it's a Foreign Key
          FKAttr := nil;
          for var Attr in Prop.GetAttributes do
            if Attr is ForeignKeyAttribute then
              FKAttr := ForeignKeyAttribute(Attr);
              
          if FKAttr <> nil then
          begin
            // It's a relationship!
            // 1. Get the DbSet for the related type
            // Note: Prop.PropertyType.Handle gives PTypeInfo
            RelatedSet := FContext.DataSet(Prop.PropertyType.Handle);
            
            // 2. Find the related entity using the FK value
            if RelatedSet <> nil then
            begin
              RelatedEntity := RelatedSet.FindObject(Val.AsVariant);
              if RelatedEntity <> nil then
                Prop.SetValue(Pointer(Result), TValue.From(RelatedEntity));
            end;
          end
          else
          begin
            // Normal Property
            // Use Robust Converter
            var ConvertedVal := TValueConverter.Convert(Val, Prop.PropertyType.Handle);
            Prop.SetValue(Pointer(Result), ConvertedVal);
          end;
        end;
      end;
    end;
  except
    // If we added to map but failed to populate, we should remove it?
    if PKVal <> '' then FIdentityMap.Remove(PKVal);
    // Result is owned by Map if added. If we remove, we must free it.
    // But if we raise, the caller won't get Result.
    // If we added to map, Map owns it.
    // If we remove from map with OwnsValues, it frees it.
    // So FIdentityMap.Remove(PKVal) will free Result.
    raise;
  end;
end;

function TDbSet<T>.FindObject(const AId: Variant): TObject;
begin
  Result := Find(AId);
end;

function TDbSet<T>.GenerateCreateTableScript: string;
var
  SB: TStringBuilder;
  Pair: TPair<string, string>;
  Prop: TRttiProperty;
  ColName, ColType: string;
  IsPK, IsAutoInc: Boolean;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('CREATE TABLE IF NOT EXISTS ').Append(GetTableName).Append(' (');
    
    First := True;
    
    // Iterate over columns
    for Pair in FColumns do
    begin
      if not First then
        SB.Append(', ');
      First := False;
      
      ColName := Pair.Value;
      Prop := FProps[ColName.ToLower];
      
      IsPK := SameText(ColName, FPKName);
      IsAutoInc := False;
      for var Attr in Prop.GetAttributes do
        if Attr is AutoIncAttribute then
          IsAutoInc := True;
          
      SB.Append(FContext.Dialect.QuoteIdentifier(ColName));
      SB.Append(' ');
      
      // Get Type from Dialect
      ColType := FContext.Dialect.GetColumnType(Prop.PropertyType.Handle, IsAutoInc);
      SB.Append(ColType);
      
      if IsPK and not IsAutoInc then // If AutoInc, Dialect usually handles PK definition (like SQLite INTEGER PRIMARY KEY)
        SB.Append(' PRIMARY KEY');
        
      // TODO: Foreign Keys?
      // SQLite supports inline FKs, but usually better to add constraints at end.
      // For "Basic" generator, we skip FK constraints for now to avoid dependency order issues.
    end;
    
    SB.Append(')');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TDbSet<T>.Add(const AEntity: T);
var
  SB: TStringBuilder;
  Cols, Vals: TStringBuilder;
  Cmd: IDbCommand;
  Pair: TPair<string, string>;
  Prop: TRttiProperty;
  Val: TValue;
  ParamName: string;
  IsAutoInc: Boolean;
  ParamsToSet: TList<TPair<string, TValue>>;
  //PKVal: string;
begin
  SB := TStringBuilder.Create;
  Cols := TStringBuilder.Create;
  Vals := TStringBuilder.Create;
  ParamsToSet := TList<TPair<string, TValue>>.Create;
  try
    SB.Append('INSERT INTO ').Append(GetTableName).Append(' (');
    
    var First := True;
    
    for Pair in FColumns do
    begin
      WriteLn('DEBUG: Processing column: ' + Pair.Value);
      Prop := FProps[Pair.Value.ToLower];
      
      // Check for AutoInc (skip PK if autoinc)
      IsAutoInc := False;
      var IsFK := False;
      
      for var Attr in Prop.GetAttributes do
      begin
        if Attr is AutoIncAttribute then IsAutoInc := True;
        if Attr is ForeignKeyAttribute then IsFK := True;
      end;
          
      if IsAutoInc then Continue;
      
      if not First then
      begin
        Cols.Append(', ');
        Vals.Append(', ');
      end;
      First := False;
      
      Cols.Append(FContext.Dialect.QuoteIdentifier(Pair.Value));
      
      ParamName := 'p_' + Pair.Value;
      Vals.Append(':').Append(ParamName);
      
      Val := Prop.GetValue(Pointer(AEntity));
      
      if IsFK then
      begin
        // Extract ID from related object
        if Val.IsObject and (Val.AsObject <> nil) then
          Val := GetRelatedId(Val.AsObject)
        else
          Val := TValue.Empty; // NULL
      end;
      
      ParamsToSet.Add(TPair<string, TValue>.Create(ParamName, Val));
    end;
    
    SB.Append(Cols.ToString).Append(') VALUES (').Append(Vals.ToString).Append(')');
    
    var CmdIntf := FContext.Connection.CreateCommand(SB.ToString);
    if not Supports(CmdIntf, StringToGUID('{20000000-0000-0000-0000-000000000004}'), Cmd) then
      raise Exception.Create('Failed to create IDbCommand');
    
    for var P in ParamsToSet do
      Cmd.AddParam(P.Key, P.Value);
      
    Cmd.ExecuteNonQuery;
    
    // TODO: If AutoInc, fetch ID back and update Entity?
    // For now, if user provided ID, we can cache it.
    // If AutoInc, we don't know ID yet, so we can't cache it easily unless we fetch it.
    // Let's skip adding to cache on Add for now to avoid complexity with AutoInc.
    // The user has the instance anyway.
    
  finally
    SB.Free;
    Cols.Free;
    Vals.Free;
    ParamsToSet.Free;
  end;
end;

procedure TDbSet<T>.Update(const AEntity: T);
var
  SB: TStringBuilder;
  Cmd: IDbCommand;
  Pair: TPair<string, string>;
  Prop: TRttiProperty;
  Val: TValue;
  ParamName: string;
  PKValue: TValue;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('UPDATE ').Append(GetTableName).Append(' SET ');
    
    First := True;
    PKValue := TValue.Empty;

    for Pair in FColumns do
    begin
      Prop := FProps[Pair.Value.ToLower];
      
      // If it is PK, store value for WHERE clause, don't update it
      if SameText(Pair.Value, FPKName) then
      begin
        PKValue := Prop.GetValue(Pointer(AEntity));
        Continue;
      end;

      if not First then
        SB.Append(', ');
      First := False;
      
      ParamName := 'p_' + Pair.Value;
      SB.Append(FContext.Dialect.QuoteIdentifier(Pair.Value))
        .Append(' = :')
        .Append(ParamName);
    end;
    
    if PKValue.IsEmpty then
      raise Exception.Create('Primary Key value is required for Update.');

    SB.Append(' WHERE ').Append(GetPKColumn).Append(' = :pk_val');
    
    Cmd := FContext.Connection.CreateCommand(SB.ToString) as IDbCommand;
    
    // Bind Params
    for Pair in FColumns do
    begin
      if SameText(Pair.Value, FPKName) then Continue;
      
      Prop := FProps[Pair.Value.ToLower];
      Val := Prop.GetValue(Pointer(AEntity));
      
      // Check for FK
      var IsFK := False;
      for var Attr in Prop.GetAttributes do
        if Attr is ForeignKeyAttribute then IsFK := True;
        
      if IsFK then
      begin
        if Val.IsObject and (Val.AsObject <> nil) then
          Val := GetRelatedId(Val.AsObject)
        else
          Val := TValue.Empty;
      end;
      
      Cmd.AddParam('p_' + Pair.Value, Val);
    end;
    
    Cmd.AddParam('pk_val', PKValue);
    Cmd.ExecuteNonQuery;
    
  finally
    SB.Free;
  end;
end;

procedure TDbSet<T>.Remove(const AEntity: T);
var
  SQL: string;
  Cmd: IDbCommand;
  Prop: TRttiProperty;
  PKValue: TValue;
  PKStr: string;
begin
  if not FProps.TryGetValue(FPKName.ToLower, Prop) then
    raise Exception.Create('Primary Key property not found.');

  PKValue := Prop.GetValue(Pointer(AEntity));
  PKStr := PKValue.ToString;
  
  SQL := Format('DELETE FROM %s WHERE %s = :pk_val', [GetTableName, GetPKColumn]);
  
  Cmd := FContext.Connection.CreateCommand(SQL) as IDbCommand;
  Cmd.AddParam('pk_val', PKValue);
  Cmd.ExecuteNonQuery;
  
  // Remove from Identity Map
  if FIdentityMap.ContainsKey(PKStr) then
    FIdentityMap.Remove(PKStr);
end;

function TDbSet<T>.Find(const AId: Variant): T;
var
  Cmd: IDbCommand;
  Reader: IDbReader;
  SQL: string;
  IdStr: string;
begin
  IdStr := VarToStr(AId);
  
  // 1. Check Identity Map
  if FIdentityMap.TryGetValue(IdStr, Result) then
    Exit;

  Result := nil;
  SQL := Format('SELECT * FROM %s WHERE %s = :id', [GetTableName, GetPKColumn]);
  
  Cmd := FContext.Connection.CreateCommand(SQL) as IDbCommand;
  Cmd.AddParam('id', TValue.FromVariant(AId));
  
  Reader := Cmd.ExecuteQuery;
  if Reader.Next then
    Result := Hydrate(Reader); // Hydrate will add to map
end;

function TDbSet<T>.List(const ASpec: ISpecification<T>): TList<T>;
var
  Generator: TSQLWhereGenerator;
  SQL: TStringBuilder;
  WhereClause: string;
  Cmd: IDbCommand;
  Reader: IDbReader;
  Param: TPair<string, TValue>;
begin
  Result := TList<T>.Create;
  Generator := TSQLWhereGenerator.Create(FContext.Dialect);
  SQL := TStringBuilder.Create;
  try
    SQL.Append('SELECT * FROM ').Append(GetTableName);
    
    // 1. Generate WHERE
    if ASpec.GetCriteria <> nil then
    begin
      WhereClause := Generator.Generate(ASpec.GetCriteria);
      if WhereClause <> '' then
        SQL.Append(' WHERE ').Append(WhereClause);
    end;
    
    // 2. Generate ORDER BY (TODO)
    
    // 3. Generate Paging
    if ASpec.IsPagingEnabled then
    begin
      SQL.Append(' ').Append(FContext.Dialect.GeneratePaging(ASpec.GetSkip, ASpec.GetTake));
    end;
    
    // 4. Execute
    Cmd := FContext.Connection.CreateCommand(SQL.ToString) as IDbCommand;
    
    for Param in Generator.Params do
      Cmd.AddParam(Param.Key, Param.Value);
      
    Reader := Cmd.ExecuteQuery;
    while Reader.Next do
      Result.Add(Hydrate(Reader));
      
  finally
    Generator.Free;
    SQL.Free;
  end;
end;

function TDbSet<T>.List: TList<T>;
begin
  // Empty spec = All
  // We need a concrete spec class or just execute SELECT *
  // For simplicity, let's implement SELECT * directly
  var Cmd := FContext.Connection.CreateCommand('SELECT * FROM ' + GetTableName) as IDbCommand;
  var Reader := Cmd.ExecuteQuery;
  Result := TList<T>.Create;
  while Reader.Next do
    Result.Add(Hydrate(Reader));
end;

function TDbSet<T>.FirstOrDefault(const ASpec: ISpecification<T>): T;
var
  ListResult: TList<T>;
begin
  // Optimization: Apply Take(1) to Spec if not already paging?
  // For now, just fetch list and take first.
  ListResult := List(ASpec);
  try
    if ListResult.Count > 0 then
    begin
      Result := ListResult[0];
      ListResult.Extract(Result); // Prevent freeing by List
    end
    else
      Result := nil;
  finally
    ListResult.Free;
  end;
end;

function TDbSet<T>.Any(const ASpec: ISpecification<T>): Boolean;
begin
  Result := Count(ASpec) > 0;
end;

function TDbSet<T>.Count(const ASpec: ISpecification<T>): Integer;
var
  Generator: TSQLWhereGenerator;
  SQL: string;
  WhereClause: string;
  Cmd: IDbCommand;
  Param: TPair<string, TValue>;
begin
  Generator := TSQLWhereGenerator.Create(FContext.Dialect);
  try
    SQL := 'SELECT COUNT(*) FROM ' + GetTableName;
    
    if ASpec.GetCriteria <> nil then
    begin
      WhereClause := Generator.Generate(ASpec.GetCriteria);
      if WhereClause <> '' then
        SQL := SQL + ' WHERE ' + WhereClause;
    end;
    
    Cmd := FContext.Connection.CreateCommand(SQL) as IDbCommand;
    for Param in Generator.Params do
      Cmd.AddParam(Param.Key, Param.Value);
      
    Result := Cmd.ExecuteScalar.AsInteger;
  finally
    Generator.Free;
  end;
end;

end.
