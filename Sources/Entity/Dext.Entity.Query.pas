unit Dext.Entity.Query;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Dext.Specifications.Interfaces;

type
  // Forward declaration
  TFluentQuery<T> = class;

  /// <summary>
  ///   Base iterator for lazy query execution.
  ///   Inherits from TEnumerator<T> to integrate with Delphi's collection system.
  /// </summary>
  TQueryIterator<T> = class(TEnumerator<T>)
  protected
    FCurrent: T;
    function DoGetCurrent: T; override;
    function DoMoveNext: Boolean; override;
    function MoveNextCore: Boolean; virtual; abstract;
  public
    constructor Create;
  end;

  /// <summary>
  ///   Concrete class for fluent queries.
  ///   Inherits from TEnumerable<T> to support for..in loops and standard collection behavior.
  /// </summary>
  TFluentQuery<T> = class(TEnumerable<T>)
  private
    FIteratorFactory: TFunc<TQueryIterator<T>>;
    FParent: TObject; // Reference to parent query for memory management
  protected
    function DoGetEnumerator: TEnumerator<T>; override;
  public
    /// <summary>
    ///   Creates a new fluent query.
    ///   @param AParent Optional parent query that this query depends on. 
    ///                  If provided, this query takes ownership and will free the parent when destroyed.
    /// </summary>
    constructor Create(const AIteratorFactory: TFunc<TQueryIterator<T>>; AParent: TObject = nil);
    destructor Destroy; override;
    
    /// <summary>
    ///   Projects each element of a sequence into a new form.
    ///   This is a generic method on a class, which is supported by Delphi.
    /// </summary>
    function Select<TResult>(const ASelector: TFunc<T, TResult>): TFluentQuery<TResult>;

    /// <summary>
    ///   Filters a sequence of values based on a predicate.
    /// </summary>
    function Where(const APredicate: TPredicate<T>): TFluentQuery<T>;

    /// <summary>
    ///   Bypasses a specified number of elements in a sequence and then returns the remaining elements.
    /// </summary>
    function Skip(const ACount: Integer): TFluentQuery<T>;

    /// <summary>
    ///   Returns a specified number of contiguous elements from the start of a sequence.
    /// </summary>
    function Take(const ACount: Integer): TFluentQuery<T>;

    /// <summary>
    ///   Force execution and return materialized list.
    /// </summary>
    function ToList: TList<T>;
  end;

  /// <summary>
  ///   Iterator that executes a specification-based query.
  /// </summary>
  TSpecificationQueryIterator<T: class> = class(TQueryIterator<T>)
  private
    FGetList: TFunc<TList<T>>;
    FList: TList<T>;
    FIndex: Integer;
    FExecuted: Boolean;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(const AGetList: TFunc<TList<T>>);
    destructor Destroy; override;
    function Clone: TQueryIterator<T>;
  end;

  /// <summary>
  ///   Iterator that projects each element of a sequence into a new form.
  /// </summary>
  TProjectingIterator<TSource, TResult> = class(TQueryIterator<TResult>)
  private
    FSource: TEnumerable<TSource>;
    FSelector: TFunc<TSource, TResult>;
    FEnumerator: TEnumerator<TSource>;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(const ASource: TEnumerable<TSource>; const ASelector: TFunc<TSource, TResult>);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that filters elements based on a predicate.
  /// </summary>
  TFilteringIterator<T> = class(TQueryIterator<T>)
  private
    FSource: TEnumerable<T>;
    FPredicate: TPredicate<T>;
    FEnumerator: TEnumerator<T>;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(const ASource: TEnumerable<T>; const APredicate: TPredicate<T>);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that skips a specified number of elements.
  /// </summary>
  TSkipIterator<T> = class(TQueryIterator<T>)
  private
    FSource: TEnumerable<T>;
    FCount: Integer;
    FEnumerator: TEnumerator<T>;
    FIndex: Integer;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(const ASource: TEnumerable<T>; const ACount: Integer);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that takes a specified number of elements.
  /// </summary>
  TTakeIterator<T> = class(TQueryIterator<T>)
  private
    FSource: TEnumerable<T>;
    FCount: Integer;
    FEnumerator: TEnumerator<T>;
    FIndex: Integer;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(const ASource: TEnumerable<T>; const ACount: Integer);
    destructor Destroy; override;
  end;

implementation

{ TQueryIterator<T> }

constructor TQueryIterator<T>.Create;
begin
  inherited Create;
end;

function TQueryIterator<T>.DoGetCurrent: T;
begin
  Result := FCurrent;
end;

function TQueryIterator<T>.DoMoveNext: Boolean;
begin
  Result := MoveNextCore;
end;

{ TFluentQuery<T> }

constructor TFluentQuery<T>.Create(const AIteratorFactory: TFunc<TQueryIterator<T>>; AParent: TObject = nil);
begin
  inherited Create;
  FIteratorFactory := AIteratorFactory;
  FParent := AParent;
end;

destructor TFluentQuery<T>.Destroy;
begin
  FParent.Free;
  inherited;
end;

function TFluentQuery<T>.DoGetEnumerator: TEnumerator<T>;
begin
  // Create a new iterator instance for each enumeration
  Result := FIteratorFactory();
end;

function TFluentQuery<T>.Select<TResult>(const ASelector: TFunc<T, TResult>): TFluentQuery<TResult>;
var
  LSource: TEnumerable<T>;
begin
  LSource := Self;
  Result := TFluentQuery<TResult>.Create(
    function: TQueryIterator<TResult>
    begin
      Result := TProjectingIterator<T, TResult>.Create(LSource, ASelector);
    end,
    Self); // Pass Self as parent
end;

function TFluentQuery<T>.Where(const APredicate: TPredicate<T>): TFluentQuery<T>;
var
  LSource: TEnumerable<T>;
begin
  LSource := Self;
  Result := TFluentQuery<T>.Create(
    function: TQueryIterator<T>
    begin
      Result := TFilteringIterator<T>.Create(LSource, APredicate);
    end,
    Self); // Pass Self as parent
end;

function TFluentQuery<T>.Skip(const ACount: Integer): TFluentQuery<T>;
var
  LSource: TEnumerable<T>;
begin
  LSource := Self;
  Result := TFluentQuery<T>.Create(
    function: TQueryIterator<T>
    begin
      Result := TSkipIterator<T>.Create(LSource, ACount);
    end,
    Self); // Pass Self as parent
end;

function TFluentQuery<T>.Take(const ACount: Integer): TFluentQuery<T>;
var
  LSource: TEnumerable<T>;
begin
  LSource := Self;
  Result := TFluentQuery<T>.Create(
    function: TQueryIterator<T>
    begin
      Result := TTakeIterator<T>.Create(LSource, ACount);
    end,
    Self); // Pass Self as parent
end;

function TFluentQuery<T>.ToList: TList<T>;
var
  Item: T;
begin
  Result := TList<T>.Create;
  try
    for Item in Self do
      Result.Add(Item);
  except
    Result.Free;
    raise;
  end;
end;

{ TSpecificationQueryIterator<T> }

constructor TSpecificationQueryIterator<T>.Create(const AGetList: TFunc<TList<T>>);
begin
  inherited Create;
  FGetList := AGetList;
  FIndex := -1;
  FExecuted := False;
end;

destructor TSpecificationQueryIterator<T>.Destroy;
begin
  FList.Free;
  inherited;
end;

function TSpecificationQueryIterator<T>.Clone: TQueryIterator<T>;
begin
  Result := TSpecificationQueryIterator<T>.Create(FGetList);
end;

function TSpecificationQueryIterator<T>.MoveNextCore: Boolean;
begin
  if not FExecuted then
  begin
    FList := FGetList();
    FExecuted := True;
  end;
  
  Inc(FIndex);
  Result := (FList <> nil) and (FIndex < FList.Count);
  
  if Result then
    FCurrent := FList[FIndex]
  else
    FCurrent := Default(T);
end;

{ TProjectingIterator<TSource, TResult> }

constructor TProjectingIterator<TSource, TResult>.Create(const ASource: TEnumerable<TSource>; const ASelector: TFunc<TSource, TResult>);
begin
  inherited Create;
  FSource := ASource;
  FSelector := ASelector;
  FEnumerator := nil;
end;

destructor TProjectingIterator<TSource, TResult>.Destroy;
begin
  FEnumerator.Free;
  inherited;
end;

function TProjectingIterator<TSource, TResult>.MoveNextCore: Boolean;
begin
  if FEnumerator = nil then
    FEnumerator := FSource.GetEnumerator;
    
  Result := FEnumerator.MoveNext;
  
  if Result then
    FCurrent := FSelector(FEnumerator.Current);
end;

{ TFilteringIterator<T> }

constructor TFilteringIterator<T>.Create(const ASource: TEnumerable<T>; const APredicate: TPredicate<T>);
begin
  inherited Create;
  FSource := ASource;
  FPredicate := APredicate;
  FEnumerator := nil;
end;

destructor TFilteringIterator<T>.Destroy;
begin
  FEnumerator.Free;
  inherited;
end;

function TFilteringIterator<T>.MoveNextCore: Boolean;
begin
  if FEnumerator = nil then
    FEnumerator := FSource.GetEnumerator;
    
  while FEnumerator.MoveNext do
  begin
    if FPredicate(FEnumerator.Current) then
    begin
      FCurrent := FEnumerator.Current;
      Exit(True);
    end;
  end;
  
  Result := False;
end;

{ TSkipIterator<T> }

constructor TSkipIterator<T>.Create(const ASource: TEnumerable<T>; const ACount: Integer);
begin
  inherited Create;
  FSource := ASource;
  FCount := ACount;
  FEnumerator := nil;
  FIndex := 0;
end;

destructor TSkipIterator<T>.Destroy;
begin
  FEnumerator.Free;
  inherited;
end;

function TSkipIterator<T>.MoveNextCore: Boolean;
begin
  if FEnumerator = nil then
  begin
    FEnumerator := FSource.GetEnumerator;
    // Skip first N elements
    while (FIndex < FCount) and FEnumerator.MoveNext do
      Inc(FIndex);
  end;
    
  Result := FEnumerator.MoveNext;
  
  if Result then
    FCurrent := FEnumerator.Current;
end;

{ TTakeIterator<T> }

constructor TTakeIterator<T>.Create(const ASource: TEnumerable<T>; const ACount: Integer);
begin
  inherited Create;
  FSource := ASource;
  FCount := ACount;
  FEnumerator := nil;
  FIndex := 0;
end;

destructor TTakeIterator<T>.Destroy;
begin
  FEnumerator.Free;
  inherited;
end;

function TTakeIterator<T>.MoveNextCore: Boolean;
begin
  if FIndex >= FCount then
    Exit(False);

  if FEnumerator = nil then
    FEnumerator := FSource.GetEnumerator;
    
  Result := FEnumerator.MoveNext;
  
  if Result then
  begin
    FCurrent := FEnumerator.Current;
    Inc(FIndex);
  end;
end;

end.
