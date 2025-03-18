#ifndef MY_TOON_SHADER_INCLUDE
#define MY_TOON_SHADER_INCLUDE

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

// material properties
CBUFFER_START(UnityPerMaterial)
    TEXTURE2D(_ColorMap);
    SAMPLER(sampler_ColorMap);
    float4 _ColorMap_ST;
    float3 _Color;
    float _Smoothness;
    float _RimSharpness;
    float3 _RimColor;
    float3 _WorldColor;
CBUFFER_END

// mesh --> vertex shader
struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 uv         : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// vertex --> frag shader
struct Varyings
{
    float4 positionHCS     : SV_POSITION;
    float2 uv              : TEXCOORD0;
    float3 positionWS      : TEXCOORD1;
    float3 normalWS        : TEXCOORD2;
    float3 viewDirectionWS : TEXCOORD3;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

float3 _LightDirection;

// Helper function for shadow bias handling
float4 GetClipSpacePosition(float3 positionWS, float3 normalWS)
{
    #if defined(SHADOW_CASTER_PASS)
        float4 positionHCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
        
        #if UNITY_REVERSED_Z
            positionHCS.z = min(positionHCS.z, positionHCS.w * UNITY_NEAR_CLIP_VALUE);
        #else
            positionHCS.z = max(positionHCS.z, positionHCS.w * UNITY_NEAR_CLIP_VALUE);
        #endif
        
        return positionHCS;
    #endif
    
    return TransformWorldToHClip(positionWS);
}

// Get shadow coordinates
float4 GetMainLightShadowCoord(float3 positionWS)
{
    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
        float4 clipPos = TransformWorldToHClip(positionWS);
        return ComputeScreenPos(clipPos);
    #else
        return TransformWorldToShadowCoord(positionWS);
    #endif
}

// Get main light with shadows
void GetMainLightData(float3 positionWS, out Light light)
{
    float4 shadowCoord = GetMainLightShadowCoord(positionWS);
    light = GetMainLight(shadowCoord);
}

// Helper function for smooth stepping with small range
float easysmoothstep(float min, float x)
{
    return smoothstep(min, min + 0.01, x);
}

Varyings Vertex(Attributes IN)
{
    Varyings OUT = (Varyings)0;
    
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
    
    OUT.positionWS = mul(unity_ObjectToWorld, IN.positionOS).xyz;
    OUT.normalWS = NormalizeNormalPerPixel(TransformObjectToWorldNormal(IN.normalOS));
    OUT.positionHCS = GetClipSpacePosition(OUT.positionWS, OUT.normalWS);
    OUT.viewDirectionWS = normalize(GetWorldSpaceViewDir(OUT.positionWS));
    OUT.uv = TRANSFORM_TEX(IN.uv, _ColorMap);
    
    return OUT;
}

float FragmentDepthOnly(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);
    return 0;
}

float4 FragmentDepthNormalsOnly(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);
    return float4(normalize(IN.normalWS), 0);
}

float3 Fragment(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);
    
    IN.normalWS = normalize(IN.normalWS);
    IN.viewDirectionWS = normalize(IN.viewDirectionWS);
    
    Light light;
    GetMainLightData(IN.positionWS, light);
    
    // Directional lighting
    float NoL = dot(IN.normalWS, light.direction);
    float toonLighting = easysmoothstep(0, NoL);
    float toonShadows = easysmoothstep(0.5, light.shadowAttenuation);
    
    // Specular highlights
    float NoH = max(dot(IN.normalWS, normalize(light.direction + IN.viewDirectionWS)), 0);
    float specularTerm = pow(NoH, _Smoothness * _Smoothness);
    specularTerm *= toonLighting * toonShadows;
    specularTerm = easysmoothstep(0.01, specularTerm);
    
    // Rim lighting
    float NoV = max(dot(IN.normalWS, IN.viewDirectionWS), 0);
    float rimTerm = pow(1.0 - NoV, _RimSharpness);
    rimTerm *= toonLighting * toonShadows;
    rimTerm = easysmoothstep(0.01, rimTerm);
    
    // Surface color
    float3 surfaceColor = _Color * SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, IN.uv);
    
    // Combine lighting components
    float3 finalLighting = _WorldColor;
    finalLighting += toonLighting * toonShadows * light.color;
    finalLighting += specularTerm * light.color;
    finalLighting += rimTerm * _RimColor;
    
    return surfaceColor * finalLighting;
}
#endif