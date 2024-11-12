# meGPT

meGPT is a conversational AI app built for iOS using Swift and SwiftUI. It leverages LM Studio for large language model capabilities, enabling interactive conversations within an app interface. The app integrates with Core Data (SwiftData) for persistent conversation storage and allows users to customize various parameters for AI responses, including temperature, top-p, max tokens, and more.

## Features

- **Persistent Conversations**: Store and retrieve chat histories with Core Data, enabling users to access previous conversations.
- **Configurable AI Settings**: Customize AI response parameters such as temperature, top-p, max tokens, and penalties.
- **Streaming Responses**: Real-time streaming of AI responses for faster interactions.
- **Dynamic Conversation Titles**: Automatically generated titles based on conversation context.
- **Secure Connection Options**: Configurable HTTP/HTTPS support with SSL error handling.
- **Haptic Feedback**: Enhanced user experience through Core Haptics for interactions.
- **Settings Management**: Modify base URL, server protocol, and model selection.

## Getting Started

### Prerequisites

- Xcode 15 or higher
- iOS 16 or later
- An instance of LM Studio or a compatible LLM server

### Installation

1. **Clone the Repository**

   `git clone https://github.com/username/GioGPT.git`

	2.	Open in Xcode
	•	Open GioGPT.xcodeproj in Xcode.
	3.	Configure Base URL
	•	In SettingsView, set the base URL for your LLM server instance, which can be updated in-app.
	4.	Run the App
	•	Build and run the app in the simulator or on a physical device.

Project Structure

	•	ChatView.swift: Main view for handling chat interface and interactions.
	•	LMStudioApiClient.swift: API client for handling requests to LM Studio, including error handling and settings management.
	•	SettingsView.swift: Settings management interface for the app, including server configurations and AI response parameter adjustments.
	•	Conversation.swift, Message.swift: Core Data models for persisting conversations and messages.

Usage

	•	Start a Conversation: Open the app, type a message, and send it to start a new conversation.
	•	Customize Settings: Access the settings menu to adjust parameters like temperature, top-p, or switch between HTTP and HTTPS.
	•	Retrieve Conversations: Access past conversations from the menu, which will display the list of saved chats with titles generated dynamically from the conversation context.
	•	Delete Conversations: Conversations can be deleted in the settings view, and they will no longer appear in the chat history.

Error Handling

The app includes comprehensive error handling, especially for network issues:
	•	SSL Errors: Notifies the user when secure connection errors occur and suggests verifying HTTPS settings.
	•	Connection Failures: Alerts the user if the server is unreachable, suggesting network troubleshooting.
	•	Server Errors: Displays HTTP error status codes for server-related issues.

Customization

The LMStudioApiClient class can be extended to include additional parameters or fine-tune the AI response behavior by modifying the payload sent to the LLM server.

Dependencies

This project has no external dependencies.

Future Enhancements

	•	Multilingual Support: Add language selection for a more inclusive experience.
	•	Further Parameter Customization: Include additional controls over AI response characteristics.
	•	Enhanced Error Messages: Provide more detailed error descriptions for improved user troubleshooting.

License

This project is licensed under the MIT License. See the LICENSE file for details.

Contributions

Contributions are welcome! Feel free to open issues or submit pull requests.
