shader_type canvas_item;
uniform float animation_time = 0.0;
uniform bool reduced_motion = false;
uniform float aspect = 1.7778;
uniform vec2 parallax = vec2(0.0);
uniform float motion_speed : hint_range(0.0,2.0) = 1.0;
uniform float star_density : hint_range(0.2,2.0) = 1.0;
uniform float nebula_brightness : hint_range(0.0,2.0) = 1.0;
uniform bool comets_enabled = true;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){float v=0.0;float a=0.5;for(int i=0;i<4;i++){v+=noise(p)*a;p=p*2.03+vec2(13.0,7.0);a*=0.5;}return v;}
void fragment(){
 vec2 uv=UV;vec2 q=vec2(uv.x*aspect,uv.y);
 float t=animation_time*motion_speed;
 vec2 drift=vec2(t*0.014,t*0.006);
 float n=fbm(q*3.0+drift+vec2(sin(t*0.1)*0.08,cos(t*0.09)*0.06));
 float wisps=fbm(q*5.0-drift*0.6);
 float blue=exp(-length((uv-vec2(0.18+sin(t*0.07)*0.05,0.72))*vec2(1.4,1.1))*2.8);
 float purple=exp(-length((uv-vec2(0.81,0.27+cos(t*0.06)*0.04))*vec2(1.1,1.4))*3.0);
 vec3 col=vec3(0.008,0.011,0.027)+nebula_brightness*vec3(0.065,0.16,0.33)*blue*(0.22+n)+nebula_brightness*vec3(0.27,0.075,0.39)*purple*(0.22+wisps);
 // Three continuous star fields with distinct drift rates: no moving scene objects.
 for(int k=0;k<3;k++){
  float layer=float(k);float grid=48.0+layer*29.0;
  vec2 moving=q+vec2(t*(0.003+layer*0.0035),-t*(0.001+layer*0.0012))+parallax*(0.002+layer*0.003);
  vec2 g=moving*grid;vec2 cell=floor(g);vec2 f=fract(g)-vec2(0.15+hash(cell+3.7)*0.7,0.15+hash(cell+15.3)*0.7);
  float h=hash(cell+layer*47.0);float r=length(f);
  float star=(1.0-smoothstep(0.018,0.095-layer*0.014,r))*step(1.0-(0.052-layer*0.009)*star_density,h);
  float glow=exp(-r*r*180.0)*step(0.994,h)*0.25;
  float twinkle=0.8+0.2*sin(t*(0.45+layer*0.13)+h*90.0);
  col+=mix(vec3(0.52,0.69,1.0),vec3(0.9,0.85,1.0),h)*(star+glow)*twinkle*(0.8-layer*0.14);
 }
 if(!reduced_motion && comets_enabled){float phase=mod(t+9.0,15.0);float active=step(11.5,phase);float u=(phase-11.5)/3.5;vec2 head=vec2(0.08+u*0.8,0.07+u*0.18);vec2 d=uv-head;float along=dot(d,normalize(vec2(0.8,0.18)));float cross_d=abs(dot(d,normalize(vec2(-0.18,0.8))));float tail=exp(-cross_d*1000.0)*smoothstep(-0.17,0.0,along)*(1.0-step(0.0,along));col+=vec3(0.55,0.68,1.0)*tail*active*0.6*sin(clamp(u,0.0,1.0)*3.14159);}
 col*=0.72+0.28*(1.0-smoothstep(0.3,0.85,length(uv-0.5)));
 COLOR=vec4(col,1.0);
}
