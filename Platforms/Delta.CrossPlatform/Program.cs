namespace Delta.CrossPlatform;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        var smokeTest = args.Contains("--smoke-test", StringComparer.OrdinalIgnoreCase);
        var address = smokeTest ? "about:blank" : args.FirstOrDefault();
        Application.Run(new BrowserWindow(address, restoreSession: !smokeTest, smokeTest: smokeTest));
    }
}