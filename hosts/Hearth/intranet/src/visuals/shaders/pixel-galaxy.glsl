const float a=1.0;
const float b=.1759;
const float PI=3.14159265359;
#define THICKNESS .11
#define ARMS 4.
#define GRID 96.
#define COLORS 2.
#define STARS 2.
#define SPEED 1.5

mat2 Rot(float a){
    float s= sin(a), c=cos(a);
    return mat2(c,-s,s,c);
}

float Hash21(vec2 p){
    p = fract(p*vec2(123.34,456.821));
    p += dot(p,p+45.32);
    return fract(p.x*p.y);
}

float spiralSDF(vec2 p,vec2 c, float phase){
    p = p - c;
    float t=atan(p.y, p.x) + phase;
    float r=length(p.xy);
    float n=(log(r/a)/b-t)/(2.*PI);

    // Cap the spiral
    float upper_r=a*exp(b*(t+2.*PI*ceil(n)));
    float lower_r=a*exp(b*(t+2.*PI*floor(n)));
    return min(abs(upper_r-r),abs(r-lower_r));
}



float Star(vec2 uv, float m, float size){
    vec2 center = uv+vec2(fract(m),fract(m*20.));
    float l = length((center));
    float v = 1.;
    // vertical trail
    v += max(0.,1.-abs(center.x*132.));
    // horizontal trail
    v += max(0.,1.-abs(center.y*132.));
    
    float brightness = ((sin(iTime+6.283*fract(m*132.4))/2.+.5)*.01+.008)*size;
    v *= brightness/l;
    // add falloff
    v*= smoothstep(.5,0.1,l);
    v = max(0.,v);
    return v;
}

void mainImage(out vec4 O,vec2 I)
{
    vec2 R=iResolution.xy;
    vec2 uv=(2.*I-R)/R.y;
    vec2 c = vec2(0.0,0.0);
    mat2 rotation = Rot(-3.14159/12.);
    // pixelate
    uv = floor(uv*GRID)/GRID;
     
    // per pixel random
    float n = (Hash21(uv)/2.-0.5);
    
    float r = length(uv);
    
    vec2 uv0 = uv;
    // warp
    uv = (uv*rotation*vec2(1.,7.));
    
    float t=1.0-THICKNESS;
    float v=0.;    
    float phase = 2.*3.14159/ARMS;
    for(float i = 0.;i<ARMS;i++){
        float d = 01.-spiralSDF(uv,vec2(c),.3*SPEED*iTime+phase*i);
        // Alter distance for a satisfying visual
        float spiral = smoothstep(t,1.,d);//;pow(d, 1.32) / 0.23;
        // add falloff away from center
        float falloff = smoothstep(.3,.5,1.-length(uv)+.5);
        //v+= falloff;
        // add pulsing effect to falloff
        falloff *=(cos((.1*SPEED*iTime+phase*i))*.8 + 1.2);
        // add to total
        spiral *= falloff;
        v += spiral;
    }
    // add depth
    
    // add LAZOR
    
    float beam = smoothstep(.93,1.,max(0.,1.-length(uv.x)));
    beam*= sin((SPEED*.4*iTime+.6-abs(-4.-uv.y))*3.14)/8.+.75;
    float trim = max(0.,(1.-length((uv.y-.9)/6.)));
    v+=(beam*trim)*(.8+sin(iTime/2.)/8.);
    /**/
    
    
    // add stars
    float star = 0.;
    //v += Star(uv1,0.128);
    
    for(float layer = 0.;layer<STARS;layer++){
        vec2 uv1 = fract(uv0*(layer+1.))-1.; 
        vec2 id = floor(uv0*(layer+1.));
        for(int y=-1;y<=1;y++){
            for(int x=-1;x<=1;x++){
                vec2 starOffset = vec2(x,y);
                float m = Hash21(id+starOffset+layer/STARS);
                float brightness = (1.-layer/STARS);
                v += Star(uv1-starOffset,m,brightness)*0.5;
            }
        }
    }/**/
    
    // add noise
    v*=n*.9+.5;
    
    
    float colorOffset = COLORS/(COLORS+1.);
    // restrict palette
    v = floor(v*COLORS+colorOffset)/COLORS;
    O.rgb = vec3(v);//*vec3(1.,.4,.6);//vec3(.35,.62,.96);
    //O.g = sin((iTime+.6-abs(-4.-uv.y))*3.14)/2.+.7;
    // O.r=n+0.5;
    
}
