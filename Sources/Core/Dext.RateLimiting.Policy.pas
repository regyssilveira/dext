unit Dext.RateLimiting.Policy;

interface

uses
  System.SysUtils,
  Dext.Http.Interfaces,
  Dext.RateLimiting.Core;

type
  /// <summary>
  ///   Fluent builder for rate limiting policies.
  /// </summary>
  TRateLimitPolicy = class
  private
    FConfig: TRateLimitConfig;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>
    ///   Creates a Fixed Window rate limiter.
    /// </summary>
    class function FixedWindow(APermitLimit, AWindowSeconds: Integer): TRateLimitPolicy; static;
    
    /// <summary>
    ///   Creates a Sliding Window rate limiter.
    /// </summary>
    class function SlidingWindow(APermitLimit, AWindowSeconds: Integer): TRateLimitPolicy; static;
    
    /// <summary>
    ///   Creates a Token Bucket rate limiter.
    /// </summary>
    class function TokenBucket(ATokenLimit, ARefillRate: Integer): TRateLimitPolicy; static;
    
    /// <summary>
    ///   Creates a Concurrency limiter.
    /// </summary>
    class function Concurrency(ALimit: Integer): TRateLimitPolicy; static;
    
    // Partition strategies
    
    /// <summary>
    ///   Partition by client IP address (default).
    /// </summary>
    function WithPartitionByIp: TRateLimitPolicy;
    
    /// <summary>
    ///   Partition by specific HTTP header.
    /// </summary>
    function WithPartitionByHeader(const AHeaderName: string): TRateLimitPolicy;
    
    /// <summary>
    ///   Partition by route path.
    /// </summary>
    function WithPartitionByRoute: TRateLimitPolicy;
    
    /// <summary>
    ///   Partition using custom function.
    /// </summary>
    function WithPartitionKey(AResolver: TPartitionKeyResolver): TRateLimitPolicy;
    
    // Global limits
    
    /// <summary>
    ///   Sets a global concurrency limit (across all partitions).
    /// </summary>
    function WithGlobalLimit(AConcurrencyLimit: Integer): TRateLimitPolicy;
    
    // Response configuration
    
    /// <summary>
    ///   Sets custom rejection message.
    /// </summary>
    function WithRejectionMessage(const AMessage: string): TRateLimitPolicy;
    
    /// <summary>
    ///   Sets custom rejection status code (default: 429).
    /// </summary>
    function WithRejectionStatusCode(AStatusCode: Integer): TRateLimitPolicy;
    
    /// <summary>
    ///   Gets the configuration.
    /// </summary>
    function Build: TRateLimitConfig;
    
    property Config: TRateLimitConfig read FConfig;
  end;

implementation

{ TRateLimitPolicy }

constructor TRateLimitPolicy.Create;
begin
  inherited Create;
  FConfig := TRateLimitConfig.Create;
end;

destructor TRateLimitPolicy.Destroy;
begin
  // Don't free FConfig here - it's transferred to middleware
  inherited;
end;

class function TRateLimitPolicy.FixedWindow(APermitLimit, AWindowSeconds: Integer): TRateLimitPolicy;
begin
  Result := TRateLimitPolicy.Create;
  Result.FConfig.LimiterType := rltFixedWindow;
  Result.FConfig.PermitLimit := APermitLimit;
  Result.FConfig.WindowSeconds := AWindowSeconds;
end;

class function TRateLimitPolicy.SlidingWindow(APermitLimit, AWindowSeconds: Integer): TRateLimitPolicy;
begin
  Result := TRateLimitPolicy.Create;
  Result.FConfig.LimiterType := rltSlidingWindow;
  Result.FConfig.PermitLimit := APermitLimit;
  Result.FConfig.WindowSeconds := AWindowSeconds;
end;

class function TRateLimitPolicy.TokenBucket(ATokenLimit, ARefillRate: Integer): TRateLimitPolicy;
begin
  Result := TRateLimitPolicy.Create;
  Result.FConfig.LimiterType := rltTokenBucket;
  Result.FConfig.TokenLimit := ATokenLimit;
  Result.FConfig.RefillRate := ARefillRate;
end;

class function TRateLimitPolicy.Concurrency(ALimit: Integer): TRateLimitPolicy;
begin
  Result := TRateLimitPolicy.Create;
  Result.FConfig.LimiterType := rltConcurrency;
  Result.FConfig.ConcurrencyLimit := ALimit;
end;

function TRateLimitPolicy.WithPartitionByIp: TRateLimitPolicy;
begin
  FConfig.PartitionStrategy := psIpAddress;
  Result := Self;
end;

function TRateLimitPolicy.WithPartitionByHeader(const AHeaderName: string): TRateLimitPolicy;
begin
  FConfig.PartitionStrategy := psHeader;
  FConfig.PartitionHeader := AHeaderName;
  Result := Self;
end;

function TRateLimitPolicy.WithPartitionByRoute: TRateLimitPolicy;
begin
  FConfig.PartitionStrategy := psRoute;
  Result := Self;
end;

function TRateLimitPolicy.WithPartitionKey(AResolver: TPartitionKeyResolver): TRateLimitPolicy;
begin
  FConfig.PartitionStrategy := psCustom;
  FConfig.PartitionResolver := AResolver;
  Result := Self;
end;

function TRateLimitPolicy.WithGlobalLimit(AConcurrencyLimit: Integer): TRateLimitPolicy;
begin
  FConfig.EnableGlobalLimit := True;
  FConfig.GlobalConcurrencyLimit := AConcurrencyLimit;
  Result := Self;
end;

function TRateLimitPolicy.WithRejectionMessage(const AMessage: string): TRateLimitPolicy;
begin
  FConfig.RejectionMessage := AMessage;
  Result := Self;
end;

function TRateLimitPolicy.WithRejectionStatusCode(AStatusCode: Integer): TRateLimitPolicy;
begin
  FConfig.RejectionStatusCode := AStatusCode;
  Result := Self;
end;

function TRateLimitPolicy.Build: TRateLimitConfig;
begin
  Result := FConfig;
end;

end.
