module IntegrationSupport
  module Constants
    BOSH_REPO_ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..'))
    BOSH_REPO_PARENT_DIR = File.expand_path(File.join(BOSH_REPO_ROOT, '..'))
    BOSH_REPO_SRC_DIR = File.join(BOSH_REPO_ROOT, 'src')
    BOSH_REPO_SRC_TMP_DIR = File.join(BOSH_REPO_SRC_DIR, 'tmp')
    INTEGRATION_BIN_DIR = File.join(BOSH_REPO_SRC_TMP_DIR, 'bin')

    SANDBOX_ASSETS_DIR = File.join(BOSH_REPO_SRC_DIR, 'spec', 'assets', 'sandbox')
    SANDBOX_CERTS_DIR = File.join(SANDBOX_ASSETS_DIR, 'ca', 'certs')

    DATABASE_CA_PATH = File.join(SANDBOX_ASSETS_DIR, 'database', 'rootCA.pem')
  end
end
