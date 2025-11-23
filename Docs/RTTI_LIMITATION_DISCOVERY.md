# 🔍 Descoberta: Limitação do RTTI do Delphi

## ❌ Problema Confirmado

**O Delphi NÃO gera RTTI de parâmetros para métodos**, mesmo com:
- `{$RTTI EXPLICIT METHODS([vcPublic, vcPublished])}`
- `{$METHODINFO ON}`
- `published` visibility
- `virtual` keyword
- Herança de `TPersistent`

### Evidência

```
Method: GetGreeting
Method.Visibility: mvPublished
Method.MethodKind: mkProcedure
GetParameters returned: 0 params  ← SEMPRE ZERO!
```

## 📚 Documentação Oficial

Segundo a documentação do Delphi, `TRttiMethod.GetParameters` **só funciona** para:
1. Métodos declarados em **interfaces**
2. Métodos **invocados via VMT** (Virtual Method Table)
3. Métodos com **calling convention especial** (safecall, etc.)

Para métodos normais de classes, o Delphi **não inclui informações de parâmetros no RTTI**.

## ✅ Soluções Possíveis

### Solução 1: Usar Atributos Personalizados (Recomendado)

Declarar os parâmetros explicitamente via atributos:

```pascal
type
  DextParamsAttribute = class(TCustomAttribute)
  private
    FParams: TArray<string>;
  public
    constructor Create(const AParams: array of string);
    property Params: TArray<string> read FParams;
  end;

[DextGet('/{name}')]
[DextParams(['Ctx: IHttpContext', 'Name: string'])]
procedure GetGreeting(Ctx: IHttpContext; const Name: string);
```

### Solução 2: Convenção sobre Configuração

Assumir que **todos** os métodos de controller seguem o padrão:
```pascal
procedure MethodName(Ctx: IHttpContext; [RouteParams...]);
```

Então o `InvokeAction` sempre injeta:
1. Primeiro parâmetro: `IHttpContext`
2. Demais parâmetros: Extraídos dos route params por nome

### Solução 3: Usar Interfaces (Mais Complexo)

Definir controllers como interfaces:

```pascal
type
  IGreetingController = interface
    ['{GUID}']
    [DextGet('/{name}')]
    procedure GetGreeting(const Name: string);
  end;
```

Interfaces **sempre** têm RTTI completo de parâmetros.

## 🎯 Recomendação

**Solução 2** é a mais pragmática para o Dext:

1. **Convenção**: Todo método de controller recebe `IHttpContext` como primeiro parâmetro
2. **Route Params**: Extraídos automaticamente por nome do path template
3. **Body**: Se o método HTTP for POST/PUT/PATCH, tentar deserializar o body

Isso elimina a necessidade de RTTI de parâmetros!

## 📝 Implementação da Solução 2

```pascal
function THandlerInvoker.InvokeAction(AInstance: TObject; AMethod: TRttiMethod): Boolean;
var
  Args: TArray<TValue>;
  RouteParams: TDictionary<string, string>;
  PathTemplate: string;
  ParamNames: TArray<string>;
begin
  // Extrair nomes dos parâmetros do path template
  // Ex: "/api/greet/{name}" -> ["name"]
  PathTemplate := GetPathTemplateFromMethod(AMethod);
  ParamNames := ExtractParamNamesFromTemplate(PathTemplate);
  
  // Montar argumentos
  SetLength(Args, 1 + Length(ParamNames));
  Args[0] := TValue.From<IHttpContext>(FContext);  // Sempre IHttpContext primeiro
  
  // Preencher route params
  RouteParams := FContext.Request.RouteParams;
  for var I := 0 to High(ParamNames) do
  begin
    if RouteParams.ContainsKey(ParamNames[I]) then
      Args[I + 1] := TValue.From<string>(RouteParams[ParamNames[I]]);
  end;
  
  // Invocar
  AMethod.Invoke(AInstance, Args);
  Result := True;
end;
```

Esta abordagem **não precisa de RTTI de parâmetros**!
