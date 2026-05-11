var logDir = "/var/log/app";
var logFile = Path.Combine(logDir, "app.log");

Directory.CreateDirectory(logDir);

var message = $"[{DateTime.UtcNow:O}] Application started successfully.\n";
await File.WriteAllTextAsync(logFile, message);

Console.WriteLine($"Log written to {logFile}");
