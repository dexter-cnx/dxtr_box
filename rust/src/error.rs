use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DxtrBoxError {
    InvalidInput {
        message: String,
    },
    UnsupportedFeature {
        feature: &'static str,
        message: String,
    },
    Engine {
        message: String,
    },
}

impl DxtrBoxError {
    pub(crate) fn engine(message: impl Into<String>) -> Self {
        Self::Engine {
            message: message.into(),
        }
    }

    pub(crate) fn invalid_input(message: impl Into<String>) -> Self {
        Self::InvalidInput {
            message: message.into(),
        }
    }

    pub(crate) fn unsupported(feature: &'static str, message: impl Into<String>) -> Self {
        Self::UnsupportedFeature {
            feature,
            message: message.into(),
        }
    }
}

impl fmt::Display for DxtrBoxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput { message } | Self::Engine { message } => f.write_str(message),
            Self::UnsupportedFeature { feature, message } => {
                write!(f, "{message} (feature: {feature})")
            }
        }
    }
}

impl std::error::Error for DxtrBoxError {}

impl From<String> for DxtrBoxError {
    fn from(message: String) -> Self {
        Self::engine(message)
    }
}
