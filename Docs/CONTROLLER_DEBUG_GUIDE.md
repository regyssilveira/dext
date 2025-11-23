# 🔍 Análise do Problema: Controllers com DI

## ❌ Problema Atual

**Sintoma**: Access Violation ao invocar método do controller
**Causa Raiz**: RTTI não está gerando informações de parâmetros do método

### Evidências dos Logs

```
🔍 InvokeAction: GetGreeting with 0 params  ← PROBLEMA AQUI!
🚀 Invoking method...
```

O método `GetGreeting(Ctx: IHttpContext; const Name: string)` tem **2 parâmetros**, mas o RTTI reporta **0**.

---

## 🎯 Por que Minimal API Funciona?

```pascal
// Minimal API - FUNCIONA
App.MapGet<string>('/greet/{name}',
  procedure(Name: string)
  begin
    // Tipos conhecidos em COMPILE TIME via generics
  end);
```

**Não precisa de RTTI** porque os tipos são passados explicitamente via generics (`<string>`).

---

## ❌ Por que Controllers Não Funcionam?

```pascal
// Controller - NÃO FUNCIONA
[DextGet('/{name}')]
procedure GetGreeting(Ctx: IHttpContext; const Name: string);
```

**Precisa de RTTI** para descobrir em runtime:
1. Quantos parâmetros o método tem
2. Qual o tipo de cada parâmetro
3. Qual o nome de cada parâmetro

---

## 🔬 Pontos de Debug

### 1. **Verificar RTTI dos Parâmetros**

**Arquivo**: `Dext.Core.HandlerInvoker.pas`, linha ~434

```pascal
function THandlerInvoker.InvokeAction(AInstance: TObject; AMethod: TRttiMethod): Boolean;
var
  Params: TArray<TRttiParameter>;
begin
  Params := AMethod.GetParameters;
  
  // ⚠️ ADICIONE ESTE DEBUG:
  WriteLn('🔍 Method: ', AMethod.Name);
  WriteLn('🔍 Params.Length: ', Length(Params));
  
  for var I := 0 to High(Params) do
  begin
    WriteLn('  Param[', I, ']: ', Params[I].Name, ' : ', Params[I].ParamType.Name);
  end;
  
  // Se Length(Params) = 0, o RTTI não foi gerado!
```

### 2. **Verificar se o Método Tem RTTI Completo**

**Teste Manual** (adicione no `ControllerExample.dpr`):

```pascal
uses
  System.Rtti;

var
  Ctx: TRttiContext;
  RttiType: TRttiType;
  Method: TRttiMethod;
begin
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(TGreetingController);
    
    WriteLn('=== RTTI Debug ===');
    for Method in RttiType.GetMethods do
    begin
      if Method.Name = 'GetGreeting' then
      begin
        WriteLn('Method: ', Method.Name);
        WriteLn('Params: ', Length(Method.GetParameters));
        
        for var Param in Method.GetParameters do
          WriteLn('  - ', Param.Name, ': ', Param.ParamType.Name);
      end;
    end;
  finally
    Ctx.Free;
  end;
end.
```

**Resultado Esperado**:
```
Method: GetGreeting
Params: 2
  - Ctx: IHttpContext
  - Name: string
```

**Se mostrar `Params: 0`**, o problema é a geração de RTTI.

---

## 🛠️ Soluções Possíveis

### Opção 1: Forçar RTTI Globalmente (Recomendado para Debug)

**Arquivo**: `ControllerExample.dpr`

Adicione no topo do arquivo:

```pascal
program ControllerExample;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) PROPERTIES([vcPublic, vcPublished]) FIELDS([vcPrivate, vcProtected, vcPublic])}

uses
  ...
```

### Opção 2: Usar Published ao invés de Public

```pascal
TGreetingController = class(TPersistent)
private
  FService: IGreetingService;
published  // ← MUDAR DE public PARA published
  constructor Create(AService: IGreetingService);
  
  [DextGet('/{name}')]
  procedure GetGreeting(Ctx: IHttpContext; const Name: string);
end;
```

**Published** sempre gera RTTI completo no Delphi.

### Opção 3: Abordagem Híbrida (Mais Robusta)

Criar um atributo que **força** o registro manual dos parâmetros:

```pascal
[DextGet('/{name}')]
[DextParams(['Ctx: IHttpContext', 'Name: string'])]  // ← Metadados explícitos
procedure GetGreeting(Ctx: IHttpContext; const Name: string);
```

---

## 📋 Checklist de Debug

1. [ ] Adicionar logs em `InvokeAction` para ver `Length(Params)`
2. [ ] Testar RTTI manualmente no `begin..end` do programa
3. [ ] Verificar se `{$METHODINFO ON}` está sendo aplicado
4. [ ] Testar com `published` ao invés de `public`
5. [ ] Verificar se `TPersistent` está sendo usado corretamente
6. [ ] Testar com `{$RTTI EXPLICIT}` global

---

## 🎯 Próximo Passo Recomendado

**Execute o teste manual de RTTI** (Opção 2 acima) para confirmar se o problema é realmente a falta de RTTI ou se há outro issue no `InvokeAction`.

Se o teste mostrar `Params: 0`, tente a **Opção 2** (usar `published`).
