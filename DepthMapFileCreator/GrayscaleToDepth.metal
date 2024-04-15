//
//  GrayscaleToDepth.metal
//  PhotonCam
//
//  Created by Photon Juniper on 2024/3/22.
//
#include <metal_stdlib>
using namespace metal;

struct converterParameters {
    float offset;
    float range;
};

// Compute kernel
kernel void grayscaleToDepth(texture2d<float, access::read>  inputTexture      [[ texture(0) ]],
                             texture2d<float, access::write> outputTexture     [[ texture(1) ]],
                             uint2 gid [[ thread_position_in_grid ]])
{
    // Don't read or write outside of the texture.
    if ((gid.x >= inputTexture.get_width()) || (gid.y >= inputTexture.get_height())) {
        return;
    }
    
    float min = 1.26269531;
    float max = 6.80859375;
    
    float grayScale = inputTexture.read(gid).x;
    float v = min + (max - min) * grayScale;
    
    float4 outputColor = float4(float3(v), 1.0);
    
    outputTexture.write(outputColor, gid);
}
