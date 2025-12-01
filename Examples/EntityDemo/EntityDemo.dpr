program EntityDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  EntityDemo.Entities in 'EntityDemo.Entities.pas',
  EntityDemo.Tests.Base in 'EntityDemo.Tests.Base.pas',
  EntityDemo.Tests.LazyLoading in 'EntityDemo.Tests.LazyLoading.pas';

procedure RunAllTests;
var
  Test: TBaseTest;
begin
  WriteLn('🚀 Dext Entity ORM Demo Suite');
  WriteLn('=============================');
  WriteLn('');

  // Run Lazy Loading Tests
  Test := TLazyLoadingTest.Create;
  try
    Test.Run;
  finally
    Test.Free;
  end;
  
  WriteLn('✨ All tests completed.');
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    RunAllTests;
  except
    on E: Exception do
      Writeln('❌ Critical Error: ', E.ClassName, ': ', E.Message);
  end;
  ReadLn;
end.
