#requires -Version 5.1
# Capture actual Windows output. The explicit fallback is a native read-only
# preview of the real .lnk files/icons, never an invented desktop photograph.
[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$Shortcuts,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class VutDesktopPhoto {
 [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);
 [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SHGetFileInfo(string p,uint a,ref Info i,uint n,uint flags);
 [DllImport("shell32.dll")] public static extern void SHChangeNotify(uint e,uint f,IntPtr a,IntPtr b);
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Info {
  public IntPtr icon;public int index;public uint attributes;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string name;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=80)] public string type;
 }
 public static bool ScreenPhoto(string output) {
  IntPtr shell=GetShellWindow();if(shell==IntPtr.Zero)return false;
  uint pid;GetWindowThreadProcessId(shell,out pid);
  if(Process.GetProcessById((int)pid).SessionId!=Process.GetCurrentProcess().SessionId)return false;
  Rectangle r=Screen.PrimaryScreen.Bounds;
  using(Bitmap b=new Bitmap(r.Width,r.Height)) {
   using(Graphics g=Graphics.FromImage(b))g.CopyFromScreen(r.Location,Point.Empty,r.Size);
   int min=255,max=0;
   for(int y=0;y<b.Height;y+=24)for(int x=0;x<b.Width;x+=24){Color c=b.GetPixel(x,y);min=Math.Min(min,Math.Min(c.R,Math.Min(c.G,c.B)));max=Math.Max(max,Math.Max(c.R,Math.Max(c.G,c.B)));}
   if(max-min<20)return false;
   b.Save(output,ImageFormat.Png);return true;
  }
 }
 public static void Preview(string[] links,string output) {
  using(Form form=new Form()) {
   form.ClientSize=new Size(1100,460);form.BackColor=Color.FromArgb(22,48,78);
   Label title=new Label();title.Text="APERÇU WINDOWS — RACCOURCIS VÉRIFIÉS";title.ForeColor=Color.White;title.Font=new Font("Segoe UI",19,FontStyle.Bold);title.SetBounds(36,28,1020,42);form.Controls.Add(title);
   Label sub=new Label();sub.Text="Quatre résultats de tests réunis pour la démonstration. Sur un PC, seul son fabricant est sélectionné.";sub.ForeColor=Color.LightSteelBlue;sub.Font=new Font("Segoe UI",11);sub.SetBounds(38,85,1020,45);form.Controls.Add(sub);
   for(int k=0;k<links.Length;k++) {
    int x=35+k*(1030/links.Length);int width=1030/links.Length-10;
    Info info=new Info();SHGetFileInfo(links[k],0,ref info,(uint)Marshal.SizeOf(typeof(Info)),0x100|0x8000);
    if(info.icon==IntPtr.Zero)throw new InvalidOperationException("Windows shortcut icon unavailable");
    PictureBox pic=new PictureBox();pic.SetBounds(x+(width-52)/2,170,52,52);pic.SizeMode=PictureBoxSizeMode.Zoom;
    using(Icon icon=Icon.FromHandle(info.icon)){pic.Image=icon.ToBitmap();}DestroyIcon(info.icon);form.Controls.Add(pic);
    Label label=new Label();label.Text=Path.GetFileNameWithoutExtension(links[k]);label.ForeColor=Color.White;label.Font=new Font("Segoe UI",11);label.TextAlign=ContentAlignment.TopCenter;label.SetBounds(x,240,width,95);form.Controls.Add(label);
   }
   Label foot=new Label();foot.Text="Vrais fichiers .lnk et icônes Windows. Installation manuelle : aucun logiciel constructeur installé pendant les tests.";foot.ForeColor=Color.LightSteelBlue;foot.Font=new Font("Segoe UI",10);foot.SetBounds(38,370,1020,55);form.Controls.Add(foot);
   form.CreateControl();using(Bitmap b=new Bitmap(form.ClientSize.Width,form.ClientSize.Height)){form.DrawToBitmap(b,new Rectangle(Point.Empty,b.Size));b.Save(output,ImageFormat.Png);}
   foreach(Control c in form.Controls){PictureBox p=c as PictureBox;if(p!=null&&p.Image!=null)p.Image.Dispose();}
  }
 }
}
'@
$output=[IO.Path]::GetFullPath($OutputDirectory);[void](New-Item -ItemType Directory -Path $output -Force)
$imagePath=Join-Path $output 'desktop-shortcuts.png'
$com=New-Object -ComObject WScript.Shell
$items=@()
try {
    foreach($path in $Shortcuts){
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Raccourci a capturer absent.'}
        $link=$com.CreateShortcut($path)
        if($link.Arguments -or -not(Test-Path -LiteralPath $link.TargetPath -PathType Leaf)){throw 'Raccourci a capturer invalide.'}
        $signature=Get-AuthenticodeSignature -LiteralPath $link.TargetPath
        if($signature.Status -ne 'Valid'){throw 'Cible de capture sans signature valide.'}
        $items+=@{Name=[IO.Path]::GetFileName($path);Signature='Valid';SHA256=(Get-FileHash $link.TargetPath).Hash;Installed=$false}
    }
}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com)}
$mode='';$screenError='';$shell=$null
try {
    $shell=New-Object -ComObject Shell.Application
    $shell.MinimizeAll();[VutDesktopPhoto]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Seconds 2
    if([VutDesktopPhoto]::ScreenPhoto($imagePath)){$mode='actual_windows_desktop_screenshot'}
}catch{$screenError=$_.Exception.Message}finally{
    if($shell){$shell.UndoMinimizeAll();[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
}
if(-not $mode){[VutDesktopPhoto]::Preview($Shortcuts,$imagePath);$mode='windows_rendered_preview_not_desktop_screenshot'}
$report=[pscustomobject]@{Mode=$mode;ImagePath=$imagePath;ImageFile='desktop-shortcuts.png';ImageSHA256=(Get-FileHash $imagePath).Hash;Shortcuts=$items;HardwareSimulated=$true;VendorInstallerExecuted=$false;ActualVendorInstallations=0;ScreenCaptureError=$screenError}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $output 'desktop-capture.json') -Encoding UTF8
return $report
