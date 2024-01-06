using UnityEngine;
using LLama.Common;
using LLama;
using System.Collections.Generic;

public class LlamaSharpTest : MonoBehaviour
{
    async void Start()
    {
        string modelPath = "/Users/juju/Downloads/calm2-7b-chat.Q2_K.gguf"; // change it to your own model path
        var prompt = "User:Do you like me?";

        // Load model
        var parameters = new ModelParams(modelPath)
        {
            ContextSize = 1024
        };
        using var model = LLamaWeights.LoadFromFile(parameters);

        // Initialize a chat session
        using var context = model.CreateContext(parameters);
        var ex = new InteractiveExecutor(context);
        ChatSession session = new ChatSession(ex);
        
        ChatHistory.Message message = new ChatHistory.Message(AuthorRole.User, prompt);
        await foreach (var text in session.ChatAsync(message, new InferenceParams() { Temperature = 0.6f, AntiPrompts = new List<string> { "User:" } }))
        {
            Debug.Log(text);
        }
    }
}
