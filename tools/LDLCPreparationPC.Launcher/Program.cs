using System;
using System.Collections.Generic;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("LDLC PrepTool")]
[assembly: AssemblyDescription("LDLC Preparation PC")]
[assembly: AssemblyCompany("LDLC")]
[assembly: AssemblyProduct("LDLC PrepTool")]
[assembly: AssemblyCopyright("Copyright LDLC")]

namespace LDLCPreparationPC.Launcher
{
    internal static class Program
    {
        private const string ScriptResourceName = "LDLCPreparationPC.ps1";

        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
                // Edition-owned startup runs before any PowerShell/bootstrap side effects.
                Type startup = Assembly.GetExecutingAssembly().GetType("PreparationEdition.Startup", false);
                if (startup != null)
                {
                    MethodInfo beforeStart = startup.GetMethod("BeforeStart", BindingFlags.Public | BindingFlags.Static);
                    if (beforeStart == null || beforeStart.ReturnType != typeof(bool))
                        throw new InvalidOperationException("Point d'entree de l'edition invalide.");
                    if (!(bool)beforeStart.Invoke(null, new object[] { args }))
                        return 0;
                }
                string script = ReadEmbeddedScript();
                Dictionary<string, object> parameters = ParseParameters(args);
                return InvokeScript(script, parameters);
            }
            catch (Exception ex)
            {
                WriteLauncherLog("Erreur fatale lanceur : " + ex);
                MessageBox.Show(
                    "LDLC PREPTOOL ne peut pas demarrer.\r\n\r\n" + ex.Message,
                    "LDLC PREPTOOL - erreur de demarrage",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }

        private static string GetRuntimeRoot()
        {
            string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            if (!string.IsNullOrWhiteSpace(programData))
            {
                return Path.Combine(programData, "LDLCPreparationPC");
            }

            return Path.Combine(Path.GetTempPath(), "LDLCPreparationPC");
        }

        private static void WriteLauncherLog(string message)
        {
            try
            {
                string runtimeRoot = GetRuntimeRoot();
                Directory.CreateDirectory(runtimeRoot);
                string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine;
                File.AppendAllText(Path.Combine(runtimeRoot, "LDLC_LAUNCHER_ERROR.log"), line, new UTF8Encoding(false));
            }
            catch
            {
            }
        }

        private static string ReadEmbeddedScript()
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream stream = assembly.GetManifestResourceStream(ScriptResourceName))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("Le script applicatif embarque est introuvable.");
                }

                using (StreamReader reader = new StreamReader(stream, new UTF8Encoding(true), true))
                {
                    return reader.ReadToEnd();
                }
            }
        }

        private static Dictionary<string, object> ParseParameters(string[] args)
        {
            Dictionary<string, object> result = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

            for (int index = 0; index < args.Length; index++)
            {
                string argument = args[index] ?? string.Empty;
                if (!argument.StartsWith("-", StringComparison.Ordinal) || argument.Length < 2)
                {
                    continue;
                }

                string token = argument.TrimStart('-');
                int separatorIndex = token.IndexOf(':');
                if (separatorIndex > 0)
                {
                    result[token.Substring(0, separatorIndex)] = token.Substring(separatorIndex + 1);
                    continue;
                }

                if (index + 1 < args.Length && !args[index + 1].StartsWith("-", StringComparison.Ordinal))
                {
                    result[token] = args[++index];
                }
                else
                {
                    result[token] = true;
                }
            }

            return result;
        }

        private static int InvokeScript(string script, Dictionary<string, object> parameters)
        {
            InitialSessionState state = InitialSessionState.CreateDefault();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();

                using (PowerShell powerShell = PowerShell.Create())
                {
                    powerShell.Runspace = runspace;
                    powerShell.AddScript(script, false);
                    foreach (KeyValuePair<string, object> parameter in parameters)
                    {
                        powerShell.AddParameter(parameter.Key, parameter.Value);
                    }

                    powerShell.Invoke();
                    if (!powerShell.HadErrors)
                    {
                        return 0;
                    }

                    StringBuilder errors = new StringBuilder();
                    foreach (ErrorRecord error in powerShell.Streams.Error)
                    {
                        if (errors.Length > 0)
                        {
                            errors.AppendLine();
                        }
                        errors.Append(error.ToString());
                    }

                    if (errors.Length == 0)
                    {
                        WriteLauncherLog(
                            "PowerShell HadErrors=True sans ErrorRecord. " +
                            "WarningCount=" + powerShell.Streams.Warning.Count + "; " +
                            "VerboseCount=" + powerShell.Streams.Verbose.Count + "; " +
                            "DebugCount=" + powerShell.Streams.Debug.Count + "; " +
                            "InformationCount=" + powerShell.Streams.Information.Count);
                        return 0;
                    }

                    WriteLauncherLog("Erreur PowerShell : " + errors);
                    throw new InvalidOperationException(
                        errors.ToString());
                }
            }
        }
    }
}
