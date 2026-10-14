// Standalone includes implementation to inspect private coefficients numerically.
#include "../../Sources/DSP/DSP.cpp"
#include <cassert>
#include <cstdio>
#include <vector>
static void stable(Coeff c) {
 assert(std::isfinite(c.b0) && std::isfinite(c.b1) && std::isfinite(c.b2));
 // Jury conditions for poles of z^2+a1*z+a2 strictly inside unit circle.
 assert(1+c.a1+c.a2>0);assert(1-c.a1+c.a2>0);assert(1-c.a2>0);
}
int main(){
 std::vector<Coeff> cases;
 for(int type=0;type<6;type++)for(double freq:{1.,20.,1000.,20000.,23999.})for(double q:{.05,.707,100.})for(double gain:{-48.,0.,48.}){
  DEQBand band{type,0,1,freq,gain,q};Coeff c=coefficients(band,48000);stable(c);cases.push_back(c);
 }
 for(auto from:cases)for(auto to:cases){
  auto delta=subtract(to,from,960);auto c=from;
  for(int step=0;step<960;step++){advance(c,delta);stable(c);}
 }
 puts("Stability tests passed: 270 extreme RBJ filters and 72,900 pairwise 960-sample coefficient ramps retain stable poles.");
}
