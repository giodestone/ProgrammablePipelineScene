/* Tessellation Domain Shader */

Texture2D heightMapTex : register(t0);
SamplerState samplerState : register(s0);

cbuffer MatrixBuffer : register(b0)
{
    matrix worldMatrix;
    matrix viewMatrix;
    matrix projectionMatrix;
};

cbuffer HeightmapBuffer : register(b1)
{
    float amplitude;
    float2 heightmapSize;
    float padding;
};

struct ConstantOutputType
{
    float edges[4] : SV_TessFactor;
    float inside[2] : SV_InsideTessFactor;
};

struct InputType
{
    float3 position : POSITION;
    float2 tex : TEXCOORD0;
    float3 normal : NORMAL;
};

struct OutputType
{
    float4 position : SV_POSITION;
    float2 tex : TEXCOORD0;
    float3 normal : NORMAL;
};

// Samples heightmap at a texel at a 0 LOD
float sampleHeightmapAt(float2 texel)
{
    return heightMapTex.SampleLevel(samplerState, texel, 0).r;
}

//Uses Sobel to get the normal at the angle
float3 getNormalAtTexel(float2 texel)
{
	//Adapted from practical rendering book

	/*Get texel value of one pixel on heightmap*/
    float2 onePx = float2(1.f / heightmapSize.x, 1.f / heightmapSize.y);

	/*Get pixels surrounding texel*/
	//0,0 is top left, 2,2 is bottom right
    float3x3 inputPixels = {
        sampleHeightmapAt(float2(texel.x - onePx.x, texel.y - onePx.y)), sampleHeightmapAt(float2(texel.x - onePx.x, texel.y)), sampleHeightmapAt(float2(texel.x - onePx.x, texel.y + onePx.y)),
        sampleHeightmapAt(float2(texel.x, texel.y - onePx.y)),           sampleHeightmapAt(float2(texel.x, texel.y)),           sampleHeightmapAt(float2(texel.x + onePx.x, texel.y)),
        sampleHeightmapAt(float2(texel.x + onePx.x, texel.y - onePx.y)), sampleHeightmapAt(float2(texel.x + onePx.x, texel.y)), sampleHeightmapAt(float2(texel.x + onePx.x, texel.y + onePx.y))
    };

	/*Add all of the values together.*/
	// 1,1 (2,2 with index 1 math notation) excluded because its always zero with sobel matrices
    float xTotal = inputPixels[0][0] - inputPixels[2][0] + 2.0f * inputPixels[0][1] - 2.0f * inputPixels[2][1] + inputPixels[0][2] - inputPixels[2][2];
    float yTotal = inputPixels[0][0] + 2.0f * inputPixels[1][0] + inputPixels[2][0] - inputPixels[0][2] - 2.0f * inputPixels[1][2] - inputPixels[2][2];

	/*Calcualte z from X and Y*/
    float z = sqrt(max(0.0f, 1.0f - xTotal * xTotal - yTotal * yTotal));

	/*Calculate normalize vetex*/
    float xAndYIntensity = 2.f;
    float zIntensity = 0.01f;
    float3 n = float3(xAndYIntensity * xTotal, zIntensity * z, xAndYIntensity * yTotal);

    return normalize(n);
}


[domain("quad")]
OutputType main(ConstantOutputType input, float2 uvwCoord : SV_DomainLocation, const OutputPatch<InputType, 4> patch)
{
    OutputType output;
	
    /*Find the position of the new vertex*/
	float3 v1 = lerp(patch[0].position, patch[1].position, uvwCoord.y);
	float3 v2 = lerp(patch[3].position, patch[2].position, uvwCoord.y);
    float3 vertexPosition = lerp(v1, v2, uvwCoord.x); // The width, height of the patch is always 1, so no other multiplcation needs to take place.

	/*Find the new postition of the texture with similar technqiue to above*/
    float2 uv1 = lerp(patch[0].tex, patch[1].tex, uvwCoord.y);
    float2 uv2 = lerp(patch[3].tex, patch[2].tex, uvwCoord.y);
    float2 uvPos = lerp(uv1, uv2, uvwCoord.x);
    output.tex = uvPos;

    /*Calculate the position of the new vertex against the world, view, and projection matrices*/
    output.position = mul(float4(vertexPosition, 1.0f), worldMatrix);

	/*Add the Y offset before view and projection matrices*/
    output.position.y = output.position.y + heightMapTex.SampleLevel(samplerState, output.tex, 0.0).r * amplitude;

    output.position = mul(output.position, viewMatrix);
    output.position = mul(output.position, projectionMatrix);

	//REMEMBER NON UNIFORM SCALING REQUIRES SPECIAL MATRIX FOR NORMALS!!! (SEE NOTES)

	/*Calculate normal using Sobel from the heightmap.*/
    output.normal = getNormalAtTexel(output.tex);
    
	return output;
}