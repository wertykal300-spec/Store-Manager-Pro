package com.storemanager.core.domain.usecase

import com.storemanager.core.domain.model.PlatformType
import com.storemanager.core.domain.model.StoreContext
import com.storemanager.core.domain.model.SystemEnvironment

class GetSystemEnvironmentUseCase {
    operator fun invoke(platform: PlatformType): SystemEnvironment {
        return SystemEnvironment(
            platform = platform,
            isLanHostCapable = (platform == PlatformType.WINDOWS)
        )
    }
}

class GetInitialStoreContextUseCase {
    operator fun invoke(): StoreContext {
        return StoreContext()
    }
}
