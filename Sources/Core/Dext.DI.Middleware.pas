unit Dext.DI.Middleware;

interface

uses
  Dext.Http.Core,
  Dext.Http.Interfaces,
  Dext.DI.Interfaces;

type
  /// <summary>
  ///   Middleware that creates a service scope per HTTP request.
  ///   This enables scoped services to be shared within a single request.
  /// </summary>
  TServiceScopeMiddleware = class(TMiddleware)
  public
    procedure Invoke(AContext: IHttpContext; ANext: TRequestDelegate); override;
  end;

  /// <summary>
  ///   Extension methods for adding service scope middleware.
  /// </summary>
  TApplicationBuilderScopeExtensions = class
  public
    /// <summary>
    ///   Adds service scope middleware to the pipeline.
    ///   This should be added early in the pipeline to ensure scoped services work correctly.
    /// </summary>
    class procedure UseServiceScope(ABuilder: IApplicationBuilder); static;
  end;

implementation

uses
  System.SysUtils;

{ TServiceScopeMiddleware }

procedure TServiceScopeMiddleware.Invoke(AContext: IHttpContext; ANext: TRequestDelegate);
var
  Scope: IServiceScope;
  ScopeInterface: IInterface;
begin
  // Create a new scope for this request
  ScopeInterface := AContext.Services.CreateScope;
  
  if not Supports(ScopeInterface, IServiceScope, Scope) then
    raise Exception.Create('Failed to create service scope');
  
  // Replace the context's service provider with the scoped one
  // This ensures all services resolved during this request use the scoped provider
  var OriginalServices := AContext.Services;
  try
    // Update context to use scoped provider
    AContext.Services := Scope.ServiceProvider;
    
    // Continue pipeline with scoped services
    ANext(AContext);
  finally
    // Restore original provider (though context is typically disposed after request)
    AContext.Services := OriginalServices;
    // Scope will be automatically disposed here (interface reference count)
  end;
end;

{ TApplicationBuilderScopeExtensions }

class procedure TApplicationBuilderScopeExtensions.UseServiceScope(ABuilder: IApplicationBuilder);
var
  Middleware: TServiceScopeMiddleware;
begin
  Middleware := TServiceScopeMiddleware.Create;
  ABuilder.UseMiddleware(Middleware);
end;

end.
