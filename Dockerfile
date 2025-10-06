FROM mcr.microsoft.com/powershell:7.4-alpine-3.18
WORKDIR /app
COPY . /app
EXPOSE 8080
CMD ["pwsh","-NoLogo","-NoProfile","-ExecutionPolicy","Bypass","-File","/app/scripture-app.ps1","-Port","8080"]
