unit Dext.Entity.Attributes;

interface

uses
  System.Rtti;

type
  TableAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  ColumnAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  PKAttribute = class(TCustomAttribute)
  end;

  AutoIncAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property as not mapped to the database.
  /// </summary>
  NotMappedAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property as a Foreign Key relationship.
  /// </summary>
  ForeignKeyAttribute = class(TCustomAttribute)
  private
    FColumnName: string;
  public
    constructor Create(const AColumnName: string);
    property ColumnName: string read FColumnName;
  end;

implementation

{ TableAttribute }

constructor TableAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ ColumnAttribute }

constructor ColumnAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ ForeignKeyAttribute }

constructor ForeignKeyAttribute.Create(const AColumnName: string);
begin
  FColumnName := AColumnName;
end;

end.
