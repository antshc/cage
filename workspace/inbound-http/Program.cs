var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://0.0.0.0:2002");

var app = builder.Build();

app.MapGet("/", async (HttpContext ctx) =>
{
    ctx.Response.ContentType = "text/plain";
    await ctx.Response.WriteAsync("OK");
    await ctx.Response.Body.FlushAsync();

    // Exit after response is flushed
    _ = Task.Run(async () =>
    {
        await Task.Delay(100);
        Environment.Exit(0);
    });
});

app.Run();
