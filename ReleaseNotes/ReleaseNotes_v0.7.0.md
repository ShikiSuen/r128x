# Release Notes - r128x v0.7.0

Released: August 2025

## English

### Major Architecture Overhaul and Modern macOS Support

r128x v0.7.0 represents a major milestone with comprehensive code modernization, enhanced format support, and updated system requirements.

#### System Requirements Update
- **macOS 14+ Required**: Dropped support for macOS 13 and earlier versions
- **Modern Platform Focus**: Optimized for latest macOS technologies and APIs

#### New Features
- **OGG File Support**: Added support for OGG Vorbis audio files
- **Enhanced UI Tracking**: Implemented TaskTrackingVM replacing NotificationCenter for better performance
- **Comprehensive Testing**: Added GTests for C-implementations ensuring code reliability

#### Architecture Improvements
- **Swiftified Backend**: Complete rewrite of EBUR128 and ExtAudioProcessor in modern Swift
- **Modern Concurrency**: Adoption of Swift's modern async/await patterns
- **Improved Testing Framework**: Comprehensive test coverage with new test targets
- **Enhanced CLI**: Fixed and improved r128x-CLI functionality

#### Technical Enhancements
- **Code Quality**: Extensive refactoring for better maintainability
- **Performance Optimization**: Better resource management and processing efficiency
- **API Modernization**: Updated to use contemporary Swift and macOS APIs
- **Documentation**: Updated screenshots and project documentation

#### Developer Experience
- **Swift Package Manager**: Full SPM integration with proper test targets
- **Code Organization**: Better separation of concerns and modular architecture
- **Build System**: Optimized build configuration for modern development workflows

---

## 简体中文

### 重大架构升级和现代 macOS 支持

r128x v0.7.0 是一个重要里程碑，具有全面的代码现代化、增强的格式支持和更新的系统要求。

#### 系统要求更新
- **需要 macOS 14+**：停止支持 macOS 13 及更早版本
- **现代平台专注**：针对最新 macOS 技术和 API 进行优化

#### 新功能
- **OGG 文件支持**：新增对 OGG Vorbis 音频文件的支持
- **增强 UI 跟踪**：实现 TaskTrackingVM 替代 NotificationCenter，提升性能
- **全面测试**：为 C 实现添加 GTests，确保代码可靠性

#### 架构改进
- **Swift 化后端**：用现代 Swift 完全重写 EBUR128 和 ExtAudioProcessor
- **现代并发**：采用 Swift 的现代 async/await 模式
- **改进测试框架**：通过新测试目标实现全面测试覆盖
- **增强 CLI**：修复并改进 r128x-CLI 功能

#### 技术增强
- **代码质量**：为提高可维护性进行大量重构
- **性能优化**：更好的资源管理和处理效率
- **API 现代化**：更新为使用现代 Swift 和 macOS API
- **文档**：更新截图和项目文档

#### 开发者体验
- **Swift Package Manager**：具有适当测试目标的完整 SPM 集成
- **代码组织**：更好的关注点分离和模块化架构
- **构建系统**：针对现代开发工作流优化构建配置

---

## 繁體中文

### 重大架構升級和現代 macOS 支援

r128x v0.7.0 是一個重要里程碑，具有全面的程式碼現代化、增強的格式支援和更新的系統需求。

#### 系統需求更新
- **需要 macOS 14+**：停止支援 macOS 13 及更早版本
- **現代平台專注**：針對最新 macOS 技術和 API 進行最佳化

#### 新功能
- **OGG 檔案支援**：新增對 OGG Vorbis 音訊檔案的支援
- **增強 UI 追蹤**：實作 TaskTrackingVM 替代 NotificationCenter，提升效能
- **全面測試**：為 C 實作新增 GTests，確保程式碼可靠性

#### 架構改進
- **Swift 化後端**：用現代 Swift 完全重寫 EBUR128 和 ExtAudioProcessor
- **現代並行**：採用 Swift 的現代 async/await 模式
- **改進測試框架**：透過新測試目標實現全面測試覆蓋
- **增強 CLI**：修復並改進 r128x-CLI 功能

#### 技術增強
- **程式碼品質**：為提高可維護性進行大量重構
- **效能最佳化**：更好的資源管理和處理效率
- **API 現代化**：更新為使用現代 Swift 和 macOS API
- **文件**：更新螢幕截圖和專案文件

#### 開發者體驗
- **Swift Package Manager**：具有適當測試目標的完整 SPM 整合
- **程式碼組織**：更好的關注點分離和模組化架構
- **建置系統**：針對現代開發工作流最佳化建置設定

---

## 日本語

### 主要アーキテクチャ刷新と現代 macOS サポート

r128x v0.7.0 は、包括的なコード現代化、拡張フォーマットサポート、更新されたシステム要件を持つ重要なマイルストーンです。

#### システム要件更新
- **macOS 14+ 必須**：macOS 13 以前のバージョンのサポートを終了
- **現代プラットフォーム重視**：最新 macOS 技術と API に最適化

#### 新機能
- **OGG ファイルサポート**：OGG Vorbis オーディオファイルのサポートを追加
- **強化された UI トラッキング**：パフォーマンス向上のため NotificationCenter を置き換える TaskTrackingVM を実装
- **包括的テスト**：コード信頼性確保のため C 実装に GTests を追加

#### アーキテクチャ改善
- **Swift 化されたバックエンド**：EBUR128 と ExtAudioProcessor の現代 Swift による完全書き直し
- **現代並行性**：Swift の現代的な async/await パターンの採用
- **改善されたテストフレームワーク**：新しいテストターゲットによる包括的テストカバレッジ
- **強化された CLI**：r128x-CLI 機能の修正と改善

#### 技術的強化
- **コード品質**：保守性向上のための大規模リファクタリング
- **パフォーマンス最適化**：より良いリソース管理と処理効率
- **API 現代化**：現代的な Swift と macOS API の使用への更新
- **ドキュメント**：スクリーンショットとプロジェクトドキュメントの更新

#### 開発者エクスペリエンス
- **Swift Package Manager**：適切なテストターゲットを持つ完全な SPM 統合
- **コード組織**：より良い関心の分離とモジュラーアーキテクチャ
- **ビルドシステム**：現代的な開発ワークフローに最適化されたビルド設定

---

## Français

### Révision Architecturale Majeure et Support macOS Moderne

r128x v0.7.0 représente un jalon majeur avec une modernisation de code complète, un support de format amélioré et des exigences système mises à jour.

#### Mise à Jour des Exigences Système
- **macOS 14+ Requis** : Abandon du support pour macOS 13 et versions antérieures
- **Focus Plateforme Moderne** : Optimisé pour les technologies et APIs macOS les plus récentes

#### Nouvelles Fonctionnalités
- **Support de Fichiers OGG** : Ajout du support pour les fichiers audio OGG Vorbis
- **Suivi UI Amélioré** : Implémentation de TaskTrackingVM remplaçant NotificationCenter pour de meilleures performances
- **Tests Complets** : Ajout de GTests pour les implémentations C assurant la fiabilité du code

#### Améliorations Architecturales
- **Backend Swiftifié** : Réécriture complète d'EBUR128 et ExtAudioProcessor en Swift moderne
- **Concurrence Moderne** : Adoption des patterns async/await modernes de Swift
- **Framework de Test Amélioré** : Couverture de test complète avec de nouveaux targets de test
- **CLI Amélioré** : Fonctionnalité r128x-CLI corrigée et améliorée

#### Améliorations Techniques
- **Qualité du Code** : Refactoring extensif pour une meilleure maintenabilité
- **Optimisation des Performances** : Meilleure gestion des ressources et efficacité de traitement
- **Modernisation d'API** : Mise à jour pour utiliser les APIs Swift et macOS contemporaines
- **Documentation** : Captures d'écran et documentation de projet mises à jour

#### Expérience Développeur
- **Swift Package Manager** : Intégration SPM complète avec des targets de test appropriés
- **Organisation du Code** : Meilleure séparation des préoccupations et architecture modulaire
- **Système de Build** : Configuration de build optimisée pour les workflows de développement modernes