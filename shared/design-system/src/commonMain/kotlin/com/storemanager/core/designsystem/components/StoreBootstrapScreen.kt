package com.storemanager.core.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.storemanager.core.designsystem.theme.StoreColors
import com.storemanager.core.domain.model.PlatformType
import com.storemanager.core.domain.model.StoreContext
import com.storemanager.core.domain.model.SystemEnvironment

@Composable
fun StoreBootstrapScreen(
    environment: SystemEnvironment,
    storeContext: StoreContext,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxSize().testTag("store_bootstrap_root"),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header Bar
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("store_header_card"),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(20.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = environment.appName,
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            text = "نظام إدارة المتاجر والمخزون والمبيعات — الأساس المشترك",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    // Platform Badge
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(20.dp))
                            .background(
                                if (environment.platform == PlatformType.WINDOWS) StoreColors.Sky500
                                else StoreColors.Indigo500
                            )
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                            .testTag("platform_indicator_badge")
                    ) {
                        Text(
                            text = environment.platform.displayName,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    }
                }
            }

            // Status Grid
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                StatusCard(
                    title = "حالة التشغيل",
                    subtitle = "نواة مشتركة تعمل بنجاح",
                    tag = "operational_status_card",
                    modifier = Modifier.weight(1f),
                    indicatorColor = StoreColors.Emerald500
                )
                StatusCard(
                    title = "نمط التخزين",
                    subtitle = environment.localFirstStorage,
                    tag = "storage_mode_card",
                    modifier = Modifier.weight(1f),
                    indicatorColor = StoreColors.Amber500
                )
            }

            // System Properties Card
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("system_specs_card"),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "مواصفات البيئة البرمجية (Phase 1A Baseline)",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )

                    SpecRow(label = "الإصدار المعماري", value = environment.architectureVersion)
                    SpecRow(label = "المنصة المستهدفة", value = "${environment.platform.displayName} (${environment.platform.osFamily})")
                    SpecRow(label = "دور الجهاز في الشبكة", value = if (environment.isLanHostCapable) "مضيف مركزي محلي (Windows Host)" else "عميل طرفي نقطة بيع (Android POS Client)")
                    SpecRow(label = "المتجر الافتراضي", value = storeContext.storeName)
                    SpecRow(label = "العملة واللغة", value = "${storeContext.defaultCurrency} | ${storeContext.defaultLanguage}")
                }
            }
        }
    }
}

@Composable
private fun StatusCard(
    title: String,
    subtitle: String,
    tag: String,
    indicatorColor: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.testTag(tag),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(12.dp)
                    .clip(CircleShape)
                    .background(indicatorColor)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
    }
}

@Composable
private fun SpecRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}
