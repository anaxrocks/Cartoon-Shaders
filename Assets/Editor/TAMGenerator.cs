using UnityEngine;
using UnityEditor;
using System.IO;

#if UNITY_EDITOR
public class TAMGenerator : EditorWindow
{
    public Texture2D[] inputTextures = new Texture2D[6];
    public string outputPath = "Assets/TAMTextures";
    
    [MenuItem("Tools/TAM Generator")]
    public static void ShowWindow()
    {
        GetWindow<TAMGenerator>("TAM Generator");
    }
    
    void OnGUI()
    {
        GUILayout.Label("Tonal Art Map Generator", EditorStyles.boldLabel);
        
        EditorGUILayout.Space();
        
        EditorGUILayout.LabelField("Input Textures (6 required)", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Add 6 textures from brightest to darkest", MessageType.Info);
        
        for (int i = 0; i < 6; i++)
        {
            inputTextures[i] = (Texture2D)EditorGUILayout.ObjectField($"Texture {i}", inputTextures[i], typeof(Texture2D), false);
        }
        
        EditorGUILayout.Space();
        
        outputPath = EditorGUILayout.TextField("Output Path", outputPath);
        
        EditorGUILayout.Space();
        
        if (GUILayout.Button("Generate TAM Textures"))
        {
            GenerateTAMTextures();
        }
    }
    
    void GenerateTAMTextures()
    {
        if (!ValidateInputTextures())
        {
            EditorUtility.DisplayDialog("Error", "Please provide all 6 input textures with the same dimensions.", "OK");
            return;
        }
        
        // Create output directory if it doesn't exist
        if (!Directory.Exists(outputPath))
        {
            Directory.CreateDirectory(outputPath);
        }
        
        int width = inputTextures[0].width;
        int height = inputTextures[0].height;
        
        Texture2D hatch0 = new Texture2D(width, height, TextureFormat.RGB24, false);
        Texture2D hatch1 = new Texture2D(width, height, TextureFormat.RGB24, false);
        
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                Color color0 = new Color(
                    inputTextures[0].GetPixel(x, y).r,
                    inputTextures[1].GetPixel(x, y).r,
                    inputTextures[2].GetPixel(x, y).r
                );
                
                Color color1 = new Color(
                    inputTextures[3].GetPixel(x, y).r,
                    inputTextures[4].GetPixel(x, y).r,
                    inputTextures[5].GetPixel(x, y).r
                );
                
                hatch0.SetPixel(x, y, color0);
                hatch1.SetPixel(x, y, color1);
            }
        }
        
        hatch0.Apply();
        hatch1.Apply();
        
        // Save textures as PNG
        byte[] hatch0Bytes = hatch0.EncodeToPNG();
        byte[] hatch1Bytes = hatch1.EncodeToPNG();
        
        string hatch0Path = Path.Combine(outputPath, "Hatch0.png");
        string hatch1Path = Path.Combine(outputPath, "Hatch1.png");
        
        File.WriteAllBytes(hatch0Path, hatch0Bytes);
        File.WriteAllBytes(hatch1Path, hatch1Bytes);
        
        AssetDatabase.Refresh();
        
        // Make sure the textures are imported with the correct settings
        TextureImporter importer0 = AssetImporter.GetAtPath(hatch0Path) as TextureImporter;
        TextureImporter importer1 = AssetImporter.GetAtPath(hatch1Path) as TextureImporter;
        
        if (importer0 != null)
        {
            importer0.textureType = TextureImporterType.Default;
            importer0.sRGBTexture = true;
            importer0.mipmapEnabled = true;
            importer0.filterMode = FilterMode.Bilinear;
            importer0.wrapMode = TextureWrapMode.Repeat;
            importer0.SaveAndReimport();
        }
        
        if (importer1 != null)
        {
            importer1.textureType = TextureImporterType.Default;
            importer1.sRGBTexture = true;
            importer1.mipmapEnabled = true;
            importer1.filterMode = FilterMode.Bilinear;
            importer1.wrapMode = TextureWrapMode.Repeat;
            importer1.SaveAndReimport();
        }
        
        EditorUtility.DisplayDialog("Success", "TAM textures generated successfully!", "OK");
    }
    
    bool ValidateInputTextures()
    {
        for (int i = 0; i < 6; i++)
        {
            if (inputTextures[i] == null)
                return false;
        }
        
        int width = inputTextures[0].width;
        int height = inputTextures[0].height;
        
        for (int i = 1; i < 6; i++)
        {
            if (inputTextures[i].width != width || inputTextures[i].height != height)
                return false;
        }
        
        return true;
    }
}
#endif