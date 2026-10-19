using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using System.Collections;

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
                form.Refresh();
                Directory.CreateDirectory(artifacts);
                using(Bitmap firstImage=new Bitmap(form.Width,form.Height)) {
                    form.DrawToBitmap(firstImage,new Rectangle(Point.Empty,firstImage.Size));
                    firstImage.Save(Path.Combine(artifacts,"ui-preview.png"),ImageFormat.Png);
                }
                Point origin=form.PointToClient(quit.PointToScreen(Point.Empty));
                Rectangle bounds=new Rectangle(origin,quit.Size);
                if(!form.ClientRectangle.Contains(bounds) || quit.Width<35 || quit.Height<12)
                    throw new InvalidOperationException("Quit button outside usable preview: window="+form.ClientSize+", button="+bounds);
                if(form.Region!=null) {
                    foreach(Point corner in new[]{new Point(bounds.Left,bounds.Top),new Point(bounds.Right-1,bounds.Top),new Point(bounds.Left,bounds.Bottom-1),new Point(bounds.Right-1,bounds.Bottom-1)})
                        if(!form.Region.IsVisible(corner)) throw new InvalidOperationException("Quit button clipped by window region at "+corner);
                }
                Size preferred=quit.GetPreferredSize(Size.Empty);
                if(preferred.Width>quit.ClientSize.Width || preferred.Height>quit.ClientSize.Height)
                    throw new InvalidOperationException("Quit button smaller than native preferred size: preferred="+preferred+", button="+quit.ClientSize);
                if(((Button)quit).TextAlign!=ContentAlignment.MiddleCenter)
                    throw new InvalidOperationException("Quit label must be centered.");
                IDictionary layout=quit.Parent.Tag as IDictionary;
                if(layout==null) throw new InvalidOperationException("Progress layout not exposed after paint.");
                RectangleF progressPanel=(RectangleF)layout["Panel"];
                if(bounds.Top<progressPanel.Bottom+2)
                    throw new InvalidOperationException("Quit button intrudes into progress panel: button="+bounds+", panel="+progressPanel);
                foreach(string key in new[]{"Status","Bar","Detail","Meta","Percent"}) {
                    RectangleF content=(RectangleF)layout[key];
                    if(!progressPanel.Contains(content) || content.IntersectsWith(bounds))
                        throw new InvalidOperationException("Progress content overlaps or escapes panel: "+key+"="+content);
                }
                using(Graphics g=quit.CreateGraphics()) {
                    Size label=TextRenderer.MeasureText(g,quit.Text,quit.Font,new Size(int.MaxValue,int.MaxValue),TextFormatFlags.SingleLine|TextFormatFlags.NoPadding);
                    if(label.Width>quit.ClientSize.Width-quit.Padding.Horizontal || label.Height>quit.ClientSize.Height-quit.Padding.Vertical)
                        throw new InvalidOperationException("Quit label clipped: label="+label+", button="+quit.ClientSize);
                }
                int whitePixels=0,minWhiteY=quit.Height,maxWhiteY=-1;
                using(Bitmap buttonImage=new Bitmap(quit.Width,quit.Height)) {
                    quit.DrawToBitmap(buttonImage,new Rectangle(Point.Empty,buttonImage.Size));
                    for(int y=0;y<buttonImage.Height;y++) for(int x=0;x<buttonImage.Width;x++) {
                        Color pixel=buttonImage.GetPixel(x,y);
                        if(pixel.R>200 && pixel.G>200 && pixel.B>200) {whitePixels++;minWhiteY=Math.Min(minWhiteY,y);maxWhiteY=Math.Max(maxWhiteY,y);}
                    }
                    if(whitePixels<10 || minWhiteY<2 || maxWhiteY>=quit.Height-2)
                        throw new InvalidOperationException("Quit label raster touches edge or is missing: pixels="+whitePixels+", top="+minWhiteY+", bottom="+maxWhiteY+", height="+quit.Height);
                }
                Directory.CreateDirectory(artifacts);
                using(Bitmap image=new Bitmap(form.Width,form.Height)) {
                    form.DrawToBitmap(image,new Rectangle(Point.Empty,image.Size));
                    image.Save(Path.Combine(artifacts,"ui-preview.png"),ImageFormat.Png);
                }
                result=String.Format(System.Globalization.CultureInfo.InvariantCulture,
                    "{{\"Visible\":true,\"MillisecondsToPreview\":{0},\"WindowWidth\":{1},\"WindowHeight\":{2},\"QuitLeft\":{3},\"QuitTop\":{4},\"QuitWidth\":{5},\"QuitHeight\":{6},\"QuitPreferredWidth\":{7},\"QuitPreferredHeight\":{8},\"QuitWhitePixels\":{9},\"QuitGlyphTop\":{10},\"QuitGlyphBottom\":{11},\"ProgressPanelBottom\":{12},\"FooterGap\":{13}}}",watch.ElapsedMilliseconds,form.ClientSize.Width,form.ClientSize.Height,bounds.Left,bounds.Top,bounds.Width,bounds.Height,preferred.Width,preferred.Height,whitePixels,minWhiteY,maxWhiteY,progressPanel.Bottom,bounds.Top-progressPanel.Bottom);
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
