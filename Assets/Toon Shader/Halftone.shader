Shader "Custom/HalftoneShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _HalftonePattern ("Halftone Pattern", 2D) = "white" {}
        _RemapMin ("Tone Remap Min", Range(0, 1)) = 0.0
        _RemapMax ("Tone Remap Max", Range(0, 1)) = 1.0
        _HalftoneSize ("Halftone Size", Range(0.1, 100)) = 10.0
        _HalftoneColor ("Halftone Color", Color) = (0, 0, 0, 1)
        _BackgroundColor ("Background Color", Color) = (1, 1, 1, 1)
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.5
        _CustomShadowBias ("Custom Shadow Bias", Range(0, 1)) = 0.01
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        // Universal Render Pipeline setup
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        ENDHLSL
        
        // Main pass with shadow receiving
        Pass
        {
            Name "ForwardLit"
            Tags {"LightMode" = "UniversalForward"}
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // Shadow-related pragmas
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float2 screenUV : TEXCOORD3;
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_HalftonePattern);
            SAMPLER(sampler_HalftonePattern);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _HalftoneSize;
                float _RemapMin;
                float _RemapMax;
                float4 _HalftoneColor;
                float4 _BackgroundColor;
                float _ShadowStrength;
                float _CustomShadowBias;
            CBUFFER_END
            
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                
                // Calculate screen UVs for the halftone pattern
                float4 screenPos = ComputeScreenPos(OUT.positionHCS);
                OUT.screenUV = screenPos.xy / screenPos.w;
                return OUT;
            }
            
            float4 frag(Varyings IN) : SV_Target
            {
                // Sample the main texture
                float4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                
                // Get lighting information
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float3 normalWS = normalize(IN.normalWS);
                float ndotl = saturate(dot(normalWS, mainLight.direction));
                
                // Apply shadows to the lighting
                float shadowAttenuation = mainLight.shadowAttenuation;
                float lightIntensity = ndotl * lerp(1.0, shadowAttenuation, _ShadowStrength);
                
                // Calculate luminance
                float luminance = dot(mainTex.rgb, float3(0.299, 0.587, 0.114));
                
                // Apply lighting and remap
                float remappedLum = lerp(_RemapMin, _RemapMax, luminance * lightIntensity);
                
                // Sample the halftone pattern with scaled screen UVs
                float2 patternUV = IN.screenUV * _HalftoneSize;
                float halftoneValue = SAMPLE_TEXTURE2D(_HalftonePattern, sampler_HalftonePattern, patternUV).r;
                
                // Apply the halftone effect
                float halftoneResult = step(halftoneValue, remappedLum);
                
                // Mix halftone color and background color
                float4 finalColor = lerp(_HalftoneColor, _BackgroundColor, halftoneResult);
                
                return finalColor;
            }
            ENDHLSL
        }
        
        // Shadow casting pass
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

            // Shadow caster specific input
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _HalftoneSize;
                float _RemapMin;
                float _RemapMax;
                float4 _HalftoneColor;
                float4 _BackgroundColor;
                float _ShadowStrength;
                float _CustomShadowBias;
            CBUFFER_END
            
            // Shadow caster structs
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv           : TEXCOORD0;
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float3 _LightDirection;

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                // Get light direction
                float3 lightDirection = _LightDirection;
                
                // Apply shadow bias using our custom parameter
                positionWS = positionWS - lightDirection * _CustomShadowBias;
                
                // Transform to clip space
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirection));

                #if UNITY_REVERSED_Z
                    output.positionCS.z = min(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    output.positionCS.z = max(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                output.uv = TRANSFORM_TEX(input.texcoord, _MainTex);
                
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                return 0;
            }
            ENDHLSL
        }
        
        // Depth-only pass for depth prepass
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

            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _HalftoneSize;
                float _RemapMin;
                float _RemapMax;
                float4 _HalftoneColor;
                float4 _BackgroundColor;
                float _ShadowStrength;
                float _CustomShadowBias;
            CBUFFER_END

            struct Attributes
            {
                float4 position     : POSITION;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv           : TEXCOORD0;
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.uv = TRANSFORM_TEX(input.texcoord, _MainTex);
                output.positionCS = TransformObjectToHClip(input.position.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                return 0;
            }
            ENDHLSL
        }
    }
}