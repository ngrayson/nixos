#define col1 vec3(1.,.8,.7)

float circle (vec2 uv, float r, float t){
    float c = 0.;
    c+= 1.-abs(length(uv)-r);
    c = smoothstep(1.-t,1.,c);
    return c;
}

vec2 rotate(vec2 p, float rad) {
    mat2 m = mat2(cos(rad), sin(rad), -sin(rad), cos(rad));
    return m * p;
}


float Hash21(vec2 p){
    p = fract(p*vec2(123.34,456.821));
    p += dot(p,p+45.32);
    return fract(p.x*p.y);
}

float star (vec2 uvs) {
    float c = 0.;
    c = 1.15-(abs(pow(abs(uvs.x),.2)*pow(abs(uvs.y),.18)));
  //  c += 1.-length(uvs)*1.8;
    c *= max(0.,1.-length(uvs)*.24);
    return c;
}
float flower (vec2 uvs) {
    float c = 0.;
    uvs *= 8.;
    c = .5-(abs(pow(abs(uvs.x),.22)*pow(abs(uvs.y),.18)));
    c+= length(uvs)*.6;
    c = 1.4-c;
    return c;
}

float shape (vec2 uvs, float n){

            // random rotation
            uvs = rotate(uvs,iTime+n);
    float c = 0.;
        /*flowers*/
    if(n>.5){
        c = flower(uvs);
    }
    /**/
    /*stars*/
    else{
        c = star(uvs);
    }
    
    return clamp(c,.0,1.);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = (2.*fragCoord-iResolution.xy)/iResolution.y;
   // uv = floor(uv*100.)/100.;
    uv = uv*vec2(.5,.5)+vec2(0.,.25);
    // warp
    vec2 uvw = uv;
    uvw.y *= abs(.8-uvw.y*.6);
    uvw = uvw* vec2(1.,1.2);
    float offset = sin(iTime)*0.03;
    float t = .02, c = 0.;
    // egg body
    c+= circle(uvw, .2, t);
    // eyeSpace
    vec2 uvi = uv + vec2( offset-.05,-0.05);
    vec2 uvn = uvi;
    uvi.y = abs(uvi.y);
    //nose/mouth
    c+= circle(uvn*vec2(2.,1.)+ vec2(0.,0.03), .014, t+.008);
    //wiglies
    c+= (sin((uv.y-iTime)*40.)*.1 +.3);
    c = floor(c);
    // flower
    c+= floor(clamp(flower(rotate((uvn*2.4)+vec2(.35,-.3),iTime/2.)),0.,1.)+.1);
    // eyes
    c+= circle(vec2(abs(uvi.x),uvi.y)+ vec2(-0.08,0.01),.03, t);
    //pupils
    c+= circle((vec2(abs(uvi.x+ offset*.2),uvi.y)+ vec2(-0.08,0.01))*vec2(2.,1.),.008, t);
    c = floor(c+.2);
    //glow
    c +=(-uv.y+.7)*.6+(sin(-iTime+uv.x*3.14)*.5+.5)*.1;
    vec3 col = min(c,1.)*col1;
    
    // falling shapes
    for(float lr =0.;lr < 1.;lr+= 1./1.){
        // wind
        vec2 uvwind = uv + vec2((-iTime+sin(iTime+lr*6.28)+lr)*.1,iTime*.8*(lr+.2))*.3;
        vec2 uvs = fract(uvwind*(8.))-.5 +lr*vec2(.4);
        vec2 id = floor(uvwind*(8.))+lr;
        for(float x=-2.;x<=2.;x++){
            for(float y=-2.;y<=2.;y++){
                vec2 offset = vec2(x,y);
                float n = Hash21(id+offset);
                // random displacement
                float s = shape(uvs-offset -vec2(fract(n*1.341),fract(n*10.231))*.8 -.5,n);
                s = floor(.2+s);
                col += s/2.* col1*.6;
            }
        }
     }
    
    // Output to screen
    fragColor = vec4(col,1.0);
}
