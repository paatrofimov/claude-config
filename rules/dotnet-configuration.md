---
paths:
  - "**/*.cs"
---

# Конфигурация в .NET

- **Не создавать `ConfigurationBuilder` вручную** (кроме тестов) – ни для чтения, ни чтобы «подмешать» значения
  по умолчанию поверх конфигурации: это ломает единый граф конфигурации и hot reload. Свои источники подключать
  в `builder.Configuration` (`HostApplicationBuilder`) или через `ConfigureAppConfiguration` (`IHostBuilder`);
  значение по умолчанию задавать в options-классе или в конфигурации приложения.
