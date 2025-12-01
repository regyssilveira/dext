unit EntityDemo.Entities;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Specifications.Base,
  Dext.Specifications.Expression,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types;

type
  TUser = class; // Forward declaration

  [Table('addresses')]
  TAddress = class
  private
    FId: Integer;
    FStreet: string;
    FCity: string;
    FUsers: TList<TUser>;
    function GetUsers: TList<TUser>; virtual;
  public
    constructor Create;
    destructor Destroy; override;

    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Street: string read FStreet write FStreet;
    property City: string read FCity write FCity;
    
    property Users: TList<TUser> read GetUsers;
  end;

  [Table('users')]
  TUser = class
  private
    FId: Integer;
    FName: string;
    FAge: Integer;
    FEmail: string;
    FCity: string;
    FAddressId: Integer;
    FAddress: TAddress;
    FContext: IInterface;  // Will hold IDbContext - using IInterface to avoid circular reference
    function GetAddress: TAddress; virtual;
    procedure SetAddress(const Value: TAddress); virtual;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;

    [Column('full_name')]
    property Name: string read FName write FName;

    property Age: Integer read FAge write FAge;
    property Email: string read FEmail write FEmail;
    property City: string read FCity write FCity;
    
    [Column('address_id')]
    property AddressId: Integer read FAddressId write FAddressId;

    [ForeignKey('AddressId', caCascade)]  // CASCADE on delete
    property Address: TAddress read GetAddress write SetAddress;
  end;

  [Table('order_items')]
  TOrderItem = class
  private
    FOrderId: Integer;
    FProductId: Integer;
    FQuantity: Integer;
    FPrice: Double;
  public
    [PK, Column('order_id')]
    property OrderId: Integer read FOrderId write FOrderId;

    [PK,Column('product_id')]
    property ProductId: Integer read FProductId write FProductId;

    property Quantity: Integer read FQuantity write FQuantity;
    property Price: Double read FPrice write FPrice;
  end;

  [Table('products')]
  TProduct = class
  private
    FId: Integer;
    FName: string;
    FPrice: Double;
    FVersion: Integer;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Price: Double read FPrice write FPrice;
    
    [Version]
    property Version: Integer read FVersion write FVersion;
  end;

  // 🧬 Metadata Implementation (TypeOf)
  UserEntity = class
  public
    class var Id: TProperty;
    class var Name: TProperty;
    class var Age: TProperty;
    class var Email: TProperty;
    class var City: TProperty;
    class var AddressId: TProperty;
    class var Address: TProperty;

    class constructor Create;
  end;

  // Specification using Metadata
  TAdultUsersSpec = class(TSpecification<TUser>)
  public
    constructor Create; override;
  end;

implementation

{ TAddress }

constructor TAddress.Create;
begin
  FUsers := TList<TUser>.Create;
end;

destructor TAddress.Destroy;
begin
  FUsers.Free;
  inherited;
end;

function TAddress.GetUsers: TList<TUser>;
begin
  // TODO : Criar automaticamente com Activator
  // Lazy initialization: Criar lista se não existe
  if FUsers = nil then
  begin
    FUsers := TList<TUser>.Create;
  end;
  
  // NOTE: Lazy Loading de coleções NÃO é automático!
  // Use Context.Entry(Address).Collection('Users').Load explicitamente
  // ou use Include ao carregar a entidade
  
  Result := FUsers;
end;

{ TUser }

function TUser.GetAddress: TAddress;
var
  Ctx: IDbContext;
begin
  // Lazy Loading: Se FAddress é nil mas temos AddressId, carregar do banco
  if (FAddress = nil) and (FAddressId > 0) and (FContext <> nil) then
  begin
    // Cast FContext to IDbContext
    if Supports(FContext, IDbContext, Ctx) then
    begin
      try
        Ctx.Entry(Self).Reference('Address').Load;
      except
        on E: Exception do
          WriteLn('DEBUG: Error loading Address: ', E.Message);
      end;
    end;
  end;
  
  Result := FAddress;
end;

procedure TUser.SetAddress(const Value: TAddress);
begin
  FAddress := Value;
end;

{ UserEntity }

class constructor UserEntity.Create;
begin
  Id := TProperty.Create('Id');
  Name := TProperty.Create('full_name');
  Age := TProperty.Create('Age');
  Email := TProperty.Create('Email');
  City := TProperty.Create('City');
  AddressId := TProperty.Create('AddressId');
  Address := TProperty.Create('Address');
end;

{ TAdultUsersSpec }

constructor TAdultUsersSpec.Create;
begin
  inherited Create;
  // Now we can use the typed metadata!
  Where(UserEntity.Age >= 18);
end;

end.
