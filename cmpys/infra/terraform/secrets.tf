# All app secrets in one Secrets Manager entry
resource "aws_secretsmanager_secret" "app" {
  name = "cmpys/${var.env}/app"
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    GEMINI_API_KEY = var.gemini_api_key
    OPENAI_API_KEY = var.openai_api_key
    YUNWU_API_KEY  = var.yunwu_api_key
    TAVILY_API_KEY = var.tavily_api_key
  })
}
