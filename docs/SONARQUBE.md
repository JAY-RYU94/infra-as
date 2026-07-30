# 기존 SonarQube 연동

SonarQube 자체는 이 클러스터에 배포하지 않습니다. Azure Pipelines Agent가 회사의
기존 SonarQube URL로 outbound 연결합니다.

## Azure DevOps Server 설정

1. Azure DevOps Server 2022.2에 SonarQube 확장 `8.2.3.2750`을 설치합니다.
2. 프로젝트 설정에서 기존 SonarQube URL과 분석 토큰을 사용하는 SonarQube
   Service Connection을 만듭니다.
3. Pipeline에는 `SonarQubePrepare@8`, `SonarQubeAnalyze@8`,
   `SonarQubePublish@8`을 사용합니다.
4. 방화벽에서 에이전트 Pod가 SonarQube URL에 접근할 수 있게 합니다. Scanner를
   Pipeline task가 내려받는 방식도 쓸 경우 `binaries.sonarsource.com`,
   `github.com`, `objects.githubusercontent.com` outbound도 허용합니다.

분석 토큰은 Azure DevOps Service Connection에만 보관합니다. Kubernetes
Secret에는 에이전트 등록용 Azure DevOps PAT만 저장합니다.

## 언어별 예제

- `pipelines/examples/sonarqube-dotnet.yml`: SDK는 저장소의 `global.json`으로
  선택합니다. 이미지에는 현재 LTS인 .NET 10과 호환용 .NET 8이 포함됩니다.
- `pipelines/examples/sonarqube-python.yml`: `.python-version` 또는
  `pyproject.toml`의 `requires-python`에 따라 `uv`가 Python을 선택하고 Agent별
  PVC에 설치·캐시합니다. 애플리케이션 Python 버전을 이미지에 고정하지 않습니다.
- `pipelines/examples/sonarqube-cpp.yml`: CMake
  `compile_commands.json`을 사용하는 CFamily 예제입니다.

C/C++ 네이티브 CFamily 분석은 기존 SonarQube의 제품/에디션과 라이선스에 따라
사용 가능 여부가 달라집니다. 기존 서버에서 CFamily가 제공되지 않으면
`cppcheck`/`clang-tidy`는 Pipeline 테스트로 계속 실행할 수 있지만, 해당 결과를
SonarQube 규칙 분석과 동일하게 취급해서는 안 됩니다. 적용 전에 SonarQube의
Administration > Marketplace/Languages에서 CFamily 지원 여부를 확인합니다.
