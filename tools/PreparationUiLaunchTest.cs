using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

public static class PreparationUiLaunchTest {
    private static Control Find(Control root, string text) {
        foreach(Control child in root.Controls) {
            if(child is Button && child.Text == text) return child;
            Control found=Find(child,text); if(found!=null) return found;
        }
        return null;
    }
    public static string Run(Assembly assembly, string artifacts) {
        Exception failure=null; bool seen=false; string result=null; int pending=0;
        Stopwatch watch=Stopwatch.StartNew();
        Action<Form> inspect=delegate(Form form) {
            try {
                if(form.IsDisposed || !form.Visible) return;
                Control next=form.Controls["ContinueButton"];
                if(next!=null) {
                    Control store=form.Controls["Store_morestel"];
                    if(store==null) throw new InvalidOperationException("Store gate has no test store.");
                    store.GetType().GetMethod("PerformClick").Invoke(store,null);
                    next.GetType().GetMethod("PerformClick").Invoke(next,null);return;
                }
                if(form.Text.IndexOf("Preview",StringComparison.OrdinalIgnoreCase)<0 || seen) return;
                Control quit=Find(form,"Quitter"); if(quit==null) return;
                Point origin=form.PointToClient(quit.PointToScreen(Point.Empty));
                Rectangle bounds=new Rectangle(origin,quit.Size);
                if(!form.ClientRectangle.Contains(bounds) || quit.Width<35 || quit.Height<12)
                    throw new InvalidOperationException("Quit button outside usable preview: window="+form.ClientSize+", button="+bounds);
                if(form.Region!=null && !form.Region.IsVisible(bounds.Left+bounds.Width/2,bounds.Bottom-1))
                    throw new InvalidOperationException("Quit button clipped by window region.");
                using(Graphics g=quit.CreateGraphics()) {
                    Size label=TextRenderer.MeasureText(g,quit.Text,quit.Font,new Size(int.MaxValue,int.MaxValue),TextFormatFlags.SingleLine|TextFormatFlags.NoPadding);
                    if(label.Width>quit.ClientSize.Width || label.Height>quit.ClientSize.Height)
                        throw new InvalidOperationException("Quit label clipped: label="+label+", button="+quit.ClientSize);
                }
                Directory.CreateDirectory(artifacts);
                using(Bitmap image=new Bitmap(form.Width,form.Height)) {
                    form.DrawToBitmap(image,new Rectangle(Point.Empty,image.Size));
                    image.Save(Path.Combine(artifacts,"ui-preview.png"),ImageFormat.Png);
                }
                result=String.Format(System.Globalization.CultureInfo.InvariantCulture,
                    "{{\"Visible\":true,\"MillisecondsToPreview\":{0},\"WindowWidth\":{1},\"WindowHeight\":{2},\"QuitLeft\":{3},\"QuitTop\":{4},\"QuitWidth\":{5},\"QuitHeight\":{6}}}",watch.ElapsedMilliseconds,form.ClientSize.Width,form.ClientSize.Height,bounds.Left,bounds.Top,bounds.Width,bounds.Height);
                seen=true;form.Close();
            } catch(Exception ex) { failure=ex;form.Close(); }
            finally {System.Threading.Interlocked.Exchange(ref pending,0);}
        };
        // PS2EXE owns a separate STA runspace. Probe without creating an HWND on
        // the caller thread, then marshal all inspection onto the form's thread.
        using(System.Threading.Timer timer=new System.Threading.Timer(delegate(object state) {
            if(seen || failure!=null) return;
            if(watch.Elapsed.TotalSeconds>40) {
                Console.Error.WriteLine("Preview test timed out; isolated test host stopped.");
                Environment.Exit(1);return;
            }
            if(System.Threading.Interlocked.Exchange(ref pending,1)!=0) return;
            try {
                Form form=Application.OpenForms.Cast<Form>().FirstOrDefault(f=>f.IsHandleCreated && !f.IsDisposed);
                if(form==null){System.Threading.Interlocked.Exchange(ref pending,0);return;}
                form.BeginInvoke(inspect,new object[]{form});
            } catch(InvalidOperationException){System.Threading.Interlocked.Exchange(ref pending,0);}
        },null,80,80)) {
            object code=assembly.EntryPoint.Invoke(null,new object[]{new string[]{"-Preview"}});
            if(failure!=null) throw failure;
            if(!seen || (code!=null && Convert.ToInt32(code)!=0)) throw new InvalidOperationException("Compiled preview did not finish successfully.");
        }
        return result;
    }
}
