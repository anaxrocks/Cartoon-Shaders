Shader "Custom/CrossHatchShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Hatch0 ("Hatch 0", 2D) = "white" {}
        _Hatch1 ("Hatch 1", 2D) = "white" {}
        _HatchScale ("Hatch Scale", Float) = 8.0
        [Toggle(USE_SCREEN_SPACE)] _UseScreenSpace("Use Screen Space", Float) = 1
        _BrightThreshold ("Bright Threshold", Range(0.5, 1.0)) = 0.9
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        
        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature USE_SCREEN_SPACE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _SHADOWS_SOFT
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
                float4 screenPos : TEXCOORD4;
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_Hatch0);
            SAMPLER(sampler_Hatch0);
            TEXTURE2D(_Hatch1);
            SAMPLER(sampler_Hatch1);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _HatchScale;
                float _BrightThreshold;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.screenPos = ComputeScreenPos(output.positionHCS);
                output.shadowCoord = TransformWorldToShadowCoord(output.positionWS);
                return output;
            }
            
            half3 Hatching(float2 uv, half intensity)
            {
                half3 hatch0 = SAMPLE_TEXTURE2D(_Hatch0, sampler_Hatch0, uv).rgb;
                half3 hatch1 = SAMPLE_TEXTURE2D(_Hatch1, sampler_Hatch1, uv).rgb;
                
                half invertedIntensity = 1.0 - intensity;
                half3 weightsA = saturate((invertedIntensity * 6.0) + half3(-0, -1, -2));
                half3 weightsB = saturate((invertedIntensity * 6.0) + half3(-3, -4, -5));
                
                weightsA.xy -= weightsA.yz;
                weightsA.z -= weightsB.x;
                weightsB.xy -= weightsB.yz;
                
                half overbright = smoothstep(_BrightThreshold, 1.0, intensity);
                
                half3 hatching = 
                    hatch0.r * weightsA.x +
                    hatch0.g * weightsA.y +
                    hatch0.b * weightsA.z +
                    hatch1.r * weightsB.x +
                    hatch1.g * weightsB.y +
                    hatch1.b * weightsB.z;
                
                return lerp(hatching, half3(1, 1, 1), overbright);
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                Light mainLight = GetMainLight(input.shadowCoord);
                float3 normalWS = normalize(input.normalWS);
                
                half NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = mainTex.rgb * mainLight.color * NdotL * mainLight.shadowAttenuation;
                half intensity = dot(diffuse, half3(0.2326, 0.7152, 0.0722));
                
                float2 hatchUV;
                #if defined(USE_SCREEN_SPACE)
                    float2 screenUV = input.screenPos.xy / input.screenPos.w;
                    hatchUV = screenUV * _ScreenParams.xy / _HatchScale;
                #else
                    hatchUV = input.uv * _HatchScale;
                #endif
                
                half3 hatch = Hatching(hatchUV, intensity);
                return half4(hatch, mainTex.a);
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _HatchScale;
                float _BrightThreshold;
            CBUFFER_END
            
            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                output.positionCS = positionCS;
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _HatchScale;
                float _BrightThreshold;
            CBUFFER_END

            struct Attributes
            {
                float4 position     : POSITION;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.position.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }
}