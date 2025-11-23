program ControllerExample;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) PROPERTIES([vcPublic, vcPublished]) FIELDS([vcPrivate, vcProtected, vcPublic])}

uses
  System.SysUtils,
  Dext.Core.Routing,
  Dext.Core.WebApplication,
  Dext.DI.Interfaces,
  Dext.DI.Extensions,
  Dext.Http.Interfaces,
  Dext.Core.Controllers,
  ControllerExample.Controller in 'ControllerExample.Controller.pas';

begin
  try
    WriteLn('🚀 Starting Dext Controller Example...');
    
    var App := TDextApplication.Create;
    
    // Register services
    TServiceCollectionExtensions.AddSingleton<IGreetingService, TGreetingService>(App.Services);
    TServiceCollectionExtensions.AddControllers(App.Services);
    
    // Map controllers
    App.MapControllers;
    
    // Run
    App.Run(8080);
  except
    on E: Exception do
      Writeln('❌ Error: ', E.ClassName, ': ', E.Message);
  end;
end.
