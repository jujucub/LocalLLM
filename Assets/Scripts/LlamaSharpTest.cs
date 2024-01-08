using UnityEngine;
using LLama.Common;
using LLama;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Cysharp.Threading.Tasks;
using TMPro;
using UnityEngine.UI;

public class LlamaSharpTest : MonoBehaviour
{
    [SerializeField] private string _modelPath = "/Users/juju/Downloads/calm2-7b-chat.Q2_K.gguf";
    
    [Header("UI")]
    [SerializeField] private CanvasGroup _canvasGroup;
    [SerializeField] private TMP_Text _text;
    [SerializeField] private TMP_InputField _inputField;
    [SerializeField] private Button _submitButton;

    private LLamaWeights _model;
    private LLamaContext _context;
    private ChatSession _chatSession;
    
    async void Start()
    {
        var parameters = new ModelParams(_modelPath)
        {
            ContextSize = 1024
        };
        _model = LLamaWeights.LoadFromFile(parameters);
        _context = _model.CreateContext(parameters);
        _chatSession = new ChatSession(new InteractiveExecutor(_context));
        
        _submitButton.onClick.AddListener(OnSubmit);
    }

    public void OnSubmit()
    {
        ChatHistory.Message message = new ChatHistory.Message(AuthorRole.User, _inputField.text);
        Chat(message).Forget();
    }

    async UniTask Chat(ChatHistory.Message message)
    {
        _canvasGroup.interactable = false;
        _text.text += "User:" + message.Content + "\n";
        await foreach (var text in _chatSession.ChatAsync(message, new InferenceParams() { Temperature = 0.6f, AntiPrompts = new List<string> { "User:" } }))
        {
            _text.text += text;
        }
        _canvasGroup.interactable = true;
    }
}
