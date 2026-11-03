// SelfCheckout Rice — X11 click-through CRT overlay.
// Written for the SelfCheckout rice.
// GLSL port of the CSS CRT stack: scanlines + grain + drift band + signal
// glitch + vignette. Click-through via X Shape empty input region.
//
// Signals: SIGUSR1 toggles visibility, SIGTERM/SIGINT exits cleanly.
// Config:  ini-style key=value at path passed as argv[1].

#define _POSIX_C_SOURCE 200809L
#define GL_GLEXT_PROTOTYPES 1

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>

#include <ctype.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static const char *VERT_SRC =
    "#version 330 core\n"
    "layout (location = 0) in vec2 aPos;\n"
    "void main() { gl_Position = vec4(aPos, 0.0, 1.0); }\n";

static const char *FRAG_SRC =
    "#version 330 core\n"
    "out vec4 FragColor;\n"
    "uniform vec2 iResolution;\n"
    "uniform float iTime;\n"
    "uniform float uOpacity;\n"
    "uniform int uReduceMotion;\n"
    "uniform int uMonitorCount;\n"
    "uniform vec4 uMonitorBounds[8];\n"
    "uniform float uMonitorOpacity[8];\n"
    "const vec3 GREEN = vec3(0.0, 1.0, 65.0/255.0);\n"
    "float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }\n"
    "float fn2(vec2 uv, float f){ float n=0.0,a=0.5; vec2 p=uv*f;"
    "  for(int i=0;i<2;i++){ n+=a*hash21(floor(p)); p*=2.0; a*=0.5; } return n; }\n"
    "void main() {\n"
    "  vec2 fc = gl_FragCoord.xy;\n"
    "  vec2 res = iResolution;\n"
    "  float op = uOpacity;\n"
    "  vec4 mb = vec4(0.0, 0.0, res.x, res.y);\n"
    "  for (int i = 0; i < uMonitorCount; i++) {\n"
    "    vec4 b = uMonitorBounds[i];\n"
    "    if (fc.x >= b.x && fc.x < b.x+b.z && fc.y >= b.y && fc.y < b.y+b.w) {\n"
    "      op = uMonitorOpacity[i]; mb = b; break;\n"
    "    }\n"
    "  }\n"
    "  vec4 ac = vec4(0.0);\n"
    "  if (mod(fc.y, 3.0) >= 2.0) { float a = 0.04; ac.rgb = GREEN*a; ac.a = a; }\n"
    "  vec4 ss = vec4(0.0);\n"
    "  float g = pow(fn2(fc, 0.85), 2.0);\n"
    "  { vec4 L = vec4(GREEN, g*0.18);\n"
    "    ss.rgb = ss.rgb*(1.0-L.a) + L.rgb*L.a; ss.a += L.a*(1.0-ss.a); }\n"
    "  float off = uReduceMotion == 0 ? mod(iTime*(47.0/9.0), 47.0) : 0.0;\n"
    "  float yt = res.y - fc.y;\n"
    "  float yp = mod(yt - off, 47.0);\n"
    "  float dA = (yp >= 11.0 && yp < 12.0) ? 0.20 : ((yp >= 29.0 && yp < 30.0) ? 0.12 : 0.0);\n"
    "  if (dA > 0.0) { vec4 L = vec4(GREEN, dA);\n"
    "    ss.rgb = ss.rgb*(1.0-L.a) + L.rgb*L.a; ss.a += L.a*(1.0-ss.a); }\n"
    "  float gO = 0.0, gY = 0.0;\n"
    "  if (uReduceMotion == 1) { gO = 0.25; gY = 0.40*res.y; }\n"
    "  else {\n"
    "    float c = mod(iTime, 13.0)/13.0;\n"
    "    if (c >= 0.29 && c < 0.32)      { float t=(c-0.29)/0.03; gO=mix(0.55,0.72,t); gY=mix(0.00,0.20,t)*res.y; }\n"
    "    else if (c >= 0.32 && c < 0.40) { float t=(c-0.32)/0.08; gO=mix(0.72,0.82,t); gY=mix(0.20,0.50,t)*res.y; }\n"
    "    else if (c >= 0.40 && c < 0.55) { float t=(c-0.40)/0.15; gO=mix(0.82,0.55,t); gY=mix(0.50,0.90,t)*res.y; }\n"
    "    else if (c >= 0.55 && c < 0.65) { float t=(c-0.55)/0.10; gO=mix(0.55,0.20,t); gY=mix(0.90,1.02,t)*res.y; }\n"
    "    else if (c >= 0.65 && c < 0.66) { float t=(c-0.65)/0.01; gO=mix(0.20,0.00,t); gY=1.02*res.y; }\n"
    "  }\n"
    "  float bl = yt - gY;\n"
    "  if (gO > 0.0 && bl >= 0.0 && bl < 36.0) {\n"
    "    float t = bl/36.0; float sh;\n"
    "    if (t < 0.2)      sh = mix(0.0, 0.10, t/0.2);\n"
    "    else if (t < 0.5) sh = mix(0.10,0.30, (t-0.2)/0.3);\n"
    "    else if (t < 0.8) sh = mix(0.30,0.10, (t-0.5)/0.3);\n"
    "    else              sh = mix(0.10,0.0,  (t-0.8)/0.2);\n"
    "    float a = sh * gO; vec4 L = vec4(GREEN, a);\n"
    "    ss.rgb = ss.rgb*(1.0-L.a) + L.rgb*L.a; ss.a += L.a*(1.0-ss.a);\n"
    "  }\n"
    "  ss.a *= op;\n"
    "  ac.rgb = ac.rgb*(1.0-ss.a) + ss.rgb*ss.a; ac.a += ss.a*(1.0-ac.a);\n"
    "  vec2 mc = mb.xy + mb.zw*0.5; vec2 mhe = mb.zw*0.5;\n"
    "  vec2 rel = (fc - mc)/mhe;\n"
    "  float vA = smoothstep(0.55, 1.0, length(rel)) * 0.45;\n"
    "  if (vA > 0.0) { ac.rgb = ac.rgb*(1.0-vA); ac.a += vA*(1.0-ac.a); }\n"
    "  FragColor = ac;\n"
    "}\n";

#define MAX_MON 8
typedef struct { char name[64]; int x,y,w,h; float opacity; } MonConf;
static struct {
    float default_opacity;
    float battery_opacity;
    int   reduce_motion; // -1 auto, 0 off, 1 on
    int   poll_ms;
    int   n_mon;
    MonConf mon[MAX_MON];
} cfg;

static void trim(char *s) {
    if (!s) return;
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n-1])) s[--n] = 0;
    size_t k = 0; while (s[k] && isspace((unsigned char)s[k])) k++;
    if (k) memmove(s, s+k, n-k+1);
}

static void load_config(const char *path) {
    cfg.default_opacity = 0.18f;
    cfg.battery_opacity = 0.05f;
    cfg.reduce_motion = -1;
    cfg.poll_ms = 2000;
    cfg.n_mon = 0;
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "crt-overlay: config not found at %s, using defaults\n", path); return; }
    char line[512];
    while (fgets(line, sizeof line, f)) {
        char *h = strchr(line, '#'); if (h) *h = 0;
        trim(line);
        if (!line[0]) continue;
        char *eq = strchr(line, '='); if (!eq) continue;
        *eq = 0; char *k = line; char *v = eq+1; trim(k); trim(v);
        if      (!strcmp(k,"default_opacity")) cfg.default_opacity = (float)atof(v);
        else if (!strcmp(k,"battery_opacity")) cfg.battery_opacity = (float)atof(v);
        else if (!strcmp(k,"poll_ms"))         cfg.poll_ms = atoi(v);
        else if (!strcmp(k,"reduce_motion")) {
            if      (!strcmp(v,"auto")) cfg.reduce_motion = -1;
            else if (!strcmp(v,"on") || !strcmp(v,"1") || !strcmp(v,"true")) cfg.reduce_motion = 1;
            else cfg.reduce_motion = 0;
        }
        else if (!strcmp(k,"monitor")) {
            if (cfg.n_mon >= MAX_MON) continue;
            MonConf *m = &cfg.mon[cfg.n_mon];
            char *p1 = strchr(v, ':'); if (!p1) continue;
            *p1 = 0; strncpy(m->name, v, sizeof m->name - 1);
            char *g = p1+1; char *p2 = strchr(g, ':'); if (!p2) continue;
            *p2 = 0;
            if (sscanf(g, "%d,%d,%d,%d", &m->x,&m->y,&m->w,&m->h) != 4) continue;
            m->opacity = (float)atof(p2+1);
            cfg.n_mon++;
        }
    }
    fclose(f);
}

static int probe_battery(void) {
    FILE *f = popen("b=$(upower -e 2>/dev/null | grep -i BAT | head -1); "
                    "[ -z \"$b\" ] && echo ac || upower -i \"$b\" 2>/dev/null | awk '/state:/{print $2}'", "r");
    if (!f) return 0;
    char buf[64] = {0};
    (void)!fgets(buf, sizeof buf, f);
    pclose(f);
    return strstr(buf, "discharging") ? 1 : 0;
}

static int probe_reduced_motion(void) {
    FILE *f = popen("gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null", "r");
    if (!f) return 0;
    char buf[32] = {0};
    (void)!fgets(buf, sizeof buf, f);
    pclose(f);
    return strstr(buf, "false") ? 1 : 0;
}

static volatile sig_atomic_t g_quit = 0, g_toggle = 0;
static void on_term(int s) { (void)s; g_quit = 1; }
static void on_usr1(int s) { (void)s; g_toggle = 1; }

static GLuint compile(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096]; glGetShaderInfoLog(s, sizeof log, NULL, log);
        fprintf(stderr, "shader compile: %s\n", log); exit(2);
    }
    return s;
}

static GLuint link_prog(GLuint v, GLuint f) {
    GLuint p = glCreateProgram();
    glAttachShader(p, v); glAttachShader(p, f);
    glLinkProgram(p);
    GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[4096]; glGetProgramInfoLog(p, sizeof log, NULL, log);
        fprintf(stderr, "program link: %s\n", log); exit(2);
    }
    return p;
}

typedef GLXContext (*glXCreateContextAttribsARBProc)(Display*, GLXFBConfig, GLXContext, Bool, const int*);

int main(int argc, char **argv) {
    const char *cfg_path = argc > 1 ? argv[1] : "config.ini";
    load_config(cfg_path);

    signal(SIGTERM, on_term);
    signal(SIGINT,  on_term);
    signal(SIGUSR1, on_usr1);

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "crt-overlay: cannot open DISPLAY\n"); return 1; }
    int screen = DefaultScreen(dpy);
    Window root = RootWindow(dpy, screen);
    int sw = DisplayWidth(dpy, screen);
    int sh = DisplayHeight(dpy, screen);

    int shape_eb, shape_err;
    if (!XShapeQueryExtension(dpy, &shape_eb, &shape_err)) {
        fprintf(stderr, "crt-overlay: X Shape extension missing\n"); return 1;
    }

    int fb_attrs[] = {
        GLX_X_RENDERABLE, True,
        GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT,
        GLX_RENDER_TYPE,   GLX_RGBA_BIT,
        GLX_X_VISUAL_TYPE, GLX_TRUE_COLOR,
        GLX_RED_SIZE,   8,
        GLX_GREEN_SIZE, 8,
        GLX_BLUE_SIZE,  8,
        GLX_ALPHA_SIZE, 8,
        GLX_DEPTH_SIZE, 0,
        GLX_DOUBLEBUFFER, True,
        None
    };
    int fbc_n;
    GLXFBConfig *fbcs = glXChooseFBConfig(dpy, screen, fb_attrs, &fbc_n);
    if (!fbcs || fbc_n == 0) {
        fprintf(stderr, "crt-overlay: no ARGB FBConfig\n"); return 1;
    }

    GLXFBConfig fbc = 0;
    XVisualInfo *vi = 0;
    for (int i = 0; i < fbc_n; i++) {
        XVisualInfo *v = glXGetVisualFromFBConfig(dpy, fbcs[i]);
        if (!v) continue;
        if (v->depth == 32) { fbc = fbcs[i]; vi = v; break; }
        XFree(v);
    }
    if (!fbc) {
        vi = glXGetVisualFromFBConfig(dpy, fbcs[0]);
        fbc = fbcs[0];
        fprintf(stderr, "crt-overlay: no 32-bit visual; overlay may not be transparent\n");
    }
    XFree(fbcs);

    Colormap cmap = XCreateColormap(dpy, root, vi->visual, AllocNone);
    XSetWindowAttributes swa = {0};
    swa.colormap = cmap;
    swa.background_pixel = 0;
    swa.border_pixel = 0;
    swa.event_mask = StructureNotifyMask;
    swa.override_redirect = False;

    Window win = XCreateWindow(dpy, root, 0, 0, sw, sh, 0, vi->depth, InputOutput,
        vi->visual,
        CWColormap|CWBackPixel|CWBorderPixel|CWEventMask|CWOverrideRedirect,
        &swa);

    XStoreName(dpy, win, "crt-overlay");
    XClassHint ch = { "crt-overlay", "crt-overlay" };
    XSetClassHint(dpy, win, &ch);

    Atom net_wm_state = XInternAtom(dpy, "_NET_WM_STATE", False);
    Atom above   = XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
    Atom sticky  = XInternAtom(dpy, "_NET_WM_STATE_STICKY", False);
    Atom skipTB  = XInternAtom(dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
    Atom skipPG  = XInternAtom(dpy, "_NET_WM_STATE_SKIP_PAGER", False);
    Atom states[] = { above, sticky, skipTB, skipPG };
    XChangeProperty(dpy, win, net_wm_state, XA_ATOM, 32, PropModeReplace,
                    (unsigned char*)states, 4);

    Atom wt = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
    Atom wt_notify = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_NOTIFICATION", False);
    XChangeProperty(dpy, win, wt, XA_ATOM, 32, PropModeReplace,
                    (unsigned char*)&wt_notify, 1);

    struct { unsigned long flags, functions, decorations; long input_mode; unsigned long status; } mwm = {2, 0, 0, 0, 0};
    Atom motif = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
    XChangeProperty(dpy, win, motif, motif, 32, PropModeReplace,
                    (unsigned char*)&mwm, 5);

    XShapeCombineRectangles(dpy, win, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);

    glXCreateContextAttribsARBProc glXCreateContextAttribsARB =
        (glXCreateContextAttribsARBProc)glXGetProcAddressARB((const GLubyte*)"glXCreateContextAttribsARB");

    int ctx_attrs[] = {
        GLX_CONTEXT_MAJOR_VERSION_ARB, 3,
        GLX_CONTEXT_MINOR_VERSION_ARB, 3,
        GLX_CONTEXT_PROFILE_MASK_ARB, GLX_CONTEXT_CORE_PROFILE_BIT_ARB,
        None
    };
    GLXContext ctx = 0;
    if (glXCreateContextAttribsARB) {
        ctx = glXCreateContextAttribsARB(dpy, fbc, NULL, True, ctx_attrs);
    }
    if (!ctx) {
        ctx = glXCreateNewContext(dpy, fbc, GLX_RGBA_TYPE, NULL, True);
    }
    if (!ctx) { fprintf(stderr, "crt-overlay: cannot create GL context\n"); return 1; }

    XMapWindow(dpy, win);
    glXMakeCurrent(dpy, win, ctx);
    XRaiseWindow(dpy, win);
    XFlush(dpy);

    GLuint v = compile(GL_VERTEX_SHADER, VERT_SRC);
    GLuint f = compile(GL_FRAGMENT_SHADER, FRAG_SRC);
    GLuint prog = link_prog(v, f);
    glDeleteShader(v); glDeleteShader(f);

    GLuint vao, vbo;
    glGenVertexArrays(1, &vao); glBindVertexArray(vao);
    float quad[] = { -1,-1, 1,-1, -1, 1, -1, 1, 1,-1, 1, 1 };
    glGenBuffers(1, &vbo); glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2*sizeof(float), (void*)0);

    GLint u_res = glGetUniformLocation(prog, "iResolution");
    GLint u_time = glGetUniformLocation(prog, "iTime");
    GLint u_op = glGetUniformLocation(prog, "uOpacity");
    GLint u_rm = glGetUniformLocation(prog, "uReduceMotion");
    GLint u_mc = glGetUniformLocation(prog, "uMonitorCount");
    GLint u_mb = glGetUniformLocation(prog, "uMonitorBounds");
    GLint u_mo = glGetUniformLocation(prog, "uMonitorOpacity");

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glViewport(0, 0, sw, sh);

    struct timespec t0; clock_gettime(CLOCK_MONOTONIC, &t0);
    int visible = 1;
    int on_battery = probe_battery();
    int rm = cfg.reduce_motion == -1 ? probe_reduced_motion() : cfg.reduce_motion;
    struct timespec last_poll = t0;

    float mon_bounds[MAX_MON*4];
    float mon_op[MAX_MON];
    for (int i = 0; i < cfg.n_mon; i++) {
        mon_bounds[i*4+0] = (float)cfg.mon[i].x;
        mon_bounds[i*4+1] = (float)(sh - cfg.mon[i].y - cfg.mon[i].h);
        mon_bounds[i*4+2] = (float)cfg.mon[i].w;
        mon_bounds[i*4+3] = (float)cfg.mon[i].h;
        mon_op[i] = cfg.mon[i].opacity;
    }

    fprintf(stderr, "crt-overlay: running on %dx%d, %d monitor(s), battery=%d reduce_motion=%d\n",
            sw, sh, cfg.n_mon, on_battery, rm);

    while (!g_quit) {
        while (XPending(dpy)) { XEvent ev; XNextEvent(dpy, &ev); }

        if (g_toggle) {
            g_toggle = 0;
            visible = !visible;
            if (visible) { XMapWindow(dpy, win); XRaiseWindow(dpy, win); }
            else         { XUnmapWindow(dpy, win); }
            XFlush(dpy);
        }

        struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        double dt_poll = (now.tv_sec - last_poll.tv_sec) + (now.tv_nsec - last_poll.tv_nsec)/1e9;
        if (dt_poll * 1000.0 >= cfg.poll_ms) {
            on_battery = probe_battery();
            if (cfg.reduce_motion == -1) rm = probe_reduced_motion();
            last_poll = now;
        }

        if (visible) {
            float op = on_battery ? cfg.battery_opacity : cfg.default_opacity;
            for (int i = 0; i < cfg.n_mon; i++) {
                mon_op[i] = on_battery ? cfg.battery_opacity : cfg.mon[i].opacity;
            }

            double et = (now.tv_sec - t0.tv_sec) + (now.tv_nsec - t0.tv_nsec)/1e9;
            glClearColor(0, 0, 0, 0);
            glClear(GL_COLOR_BUFFER_BIT);
            glUseProgram(prog);
            glUniform2f(u_res, (float)sw, (float)sh);
            glUniform1f(u_time, (float)et);
            glUniform1f(u_op, op);
            glUniform1i(u_rm, rm);
            glUniform1i(u_mc, cfg.n_mon);
            if (cfg.n_mon > 0) {
                glUniform4fv(u_mb, cfg.n_mon, mon_bounds);
                glUniform1fv(u_mo, cfg.n_mon, mon_op);
            }
            glBindVertexArray(vao);
            glDrawArrays(GL_TRIANGLES, 0, 6);
            glXSwapBuffers(dpy, win);
        } else {
            struct timespec s = { 0, 50*1000*1000 };
            nanosleep(&s, NULL);
        }
    }

    glXMakeCurrent(dpy, None, NULL);
    glXDestroyContext(dpy, ctx);
    XDestroyWindow(dpy, win);
    XFreeColormap(dpy, cmap);
    XFree(vi);
    XCloseDisplay(dpy);
    return 0;
}
